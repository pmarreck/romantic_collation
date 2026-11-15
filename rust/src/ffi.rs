//! The public header's checked ABI, with panic containment at each fallible edge.
use crate::{Collator, Error};
use std::{
    alloc::{Layout, alloc, dealloc},
    panic::{AssertUnwindSafe, catch_unwind},
    ptr,
};

#[repr(C)]
pub struct Config {
    struct_size: usize,
    abi_version: u32,
    options: u32,
}
fn guard(f: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(6)
}
fn status(error: Error) -> i32 {
    match error {
        Error::OutOfMemory => 2,
        Error::UnsupportedOption => 5,
    }
}
unsafe fn bytes<'a>(p: *const u8, len: usize) -> Option<&'a [u8]> {
    if len == 0 {
        return Some(&[]);
    }
    if p.is_null() || len > isize::MAX as usize {
        return None;
    }
    Some(unsafe { std::slice::from_raw_parts(p, len) })
}

#[unsafe(no_mangle)]
pub extern "C" fn rcol_version() -> *const std::ffi::c_char {
    c"0.1.0".as_ptr()
}
#[unsafe(no_mangle)]
pub extern "C" fn rcol_ordering_version() -> u32 {
    1
}

/// # Safety
/// Configuration/output pointers must refer to the objects described in the C header.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rcol_open(cfg: *const Config, out: *mut *mut Collator) -> i32 {
    guard(|| {
        if out.is_null() {
            return 1;
        }
        unsafe {
            out.write(ptr::null_mut());
        }
        if cfg.is_null() {
            return 1;
        }
        let cfg = unsafe { &*cfg };
        if cfg.struct_size < std::mem::offset_of!(Config, options) + 4 {
            return 1;
        }
        if cfg.abi_version != 1 {
            return 4;
        }
        let coll = match Collator::new(cfg.options) {
            Ok(c) => c,
            Err(e) => return status(e),
        };
        let p = unsafe { alloc(Layout::new::<Collator>()) as *mut Collator };
        if p.is_null() {
            return 2;
        }
        unsafe {
            p.write(coll);
            out.write(p);
        }
        0
    })
}

/// # Safety
/// Pass NULL or a live handle from this library, after all concurrent calls finish.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rcol_close(coll: *mut Collator) {
    if !coll.is_null() {
        unsafe {
            ptr::drop_in_place(coll);
            dealloc(coll.cast(), Layout::new::<Collator>());
        }
    }
}

/// # Safety
/// Handles, byte ranges and writable result pointers must obey the public header.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rcol_compare_utf8(
    coll: *const Collator,
    a: *const u8,
    alen: usize,
    b: *const u8,
    blen: usize,
    out: *mut i32,
) -> i32 {
    guard(|| {
        if coll.is_null() || out.is_null() {
            return 1;
        }
        let (Some(a), Some(b)) = (unsafe { bytes(a, alen) }, unsafe { bytes(b, blen) }) else {
            return 1;
        };
        match unsafe { &*coll }.compare(a, b) {
            Ok(order) => {
                unsafe {
                    out.write(match order {
                        std::cmp::Ordering::Less => -1,
                        std::cmp::Ordering::Equal => 0,
                        std::cmp::Ordering::Greater => 1,
                    });
                }
                0
            }
            Err(e) => status(e),
        }
    })
}

/// # Safety
/// Byte ranges, capacity and writable length pointers must obey the public header.
/// Input/output byte buffers may overlap; handles may be shared read-only.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rcol_sort_key_utf8(
    coll: *const Collator,
    input: *const u8,
    len: usize,
    out: *mut u8,
    cap: usize,
    required: *mut usize,
) -> i32 {
    guard(|| {
        if required.is_null() {
            return 1;
        }
        unsafe {
            required.write(0);
        }
        if coll.is_null() || (out.is_null() && cap != 0) {
            return 1;
        }
        let Some(input) = (unsafe { bytes(input, len) }) else {
            return 1;
        };
        let coll = unsafe { &*coll };
        if coll.options & 1 != 0 {
            let Some(need) = len.checked_add(1) else {
                return 2;
            };
            unsafe {
                required.write(need);
            }
            if cap == 0 {
                return 0;
            }
            if cap < need {
                return 3;
            }
            unsafe {
                ptr::copy(input.as_ptr(), out, len);
                out.add(len).write(0);
            }
            return 0;
        }
        let key = match coll.sort_key(input) {
            Ok(k) => k,
            Err(e) => return status(e),
        };
        unsafe {
            required.write(key.len());
        }
        if cap == 0 {
            return 0;
        }
        if cap < key.len() {
            return 3;
        }
        unsafe {
            ptr::copy_nonoverlapping(key.as_ptr(), out, key.len());
        }
        0
    })
}
#[unsafe(no_mangle)]
pub extern "C" fn rcol_status_name(value: i32) -> *const std::ffi::c_char {
    match value {
        0 => c"ok",
        1 => c"invalid argument",
        2 => c"out of memory",
        3 => c"buffer too small",
        4 => c"unsupported ABI version",
        5 => c"unsupported option",
        6 => c"internal error",
        _ => c"unknown status",
    }
    .as_ptr()
}
