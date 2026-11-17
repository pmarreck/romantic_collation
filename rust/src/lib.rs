//! Independent Rust implementation. Zig defines ordering revision 2.
#![deny(clippy::unwrap_used, clippy::expect_used)]
mod core;
mod ffi;
mod tables;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    OutOfMemory,
    UnsupportedOption,
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::OutOfMemory => "out of memory",
            Self::UnsupportedOption => "unsupported option",
        })
    }
}
impl std::error::Error for Error {}

pub mod options {
    pub const CODE_POINT: u32 = 1;
    pub const DECIMAL: u32 = 8;
    pub const DECIMAL_COMMA: u32 = 16;
    pub const SCIENTIFIC: u32 = 32;
    pub const ROMAN: u32 = 64;
}

/// The default house order or explicitly selected numeric/code-point options.
#[derive(Clone, Debug)]
pub struct Collator {
    options: u32,
}
impl Collator {
    pub fn new(options: u32) -> Result<Self, Error> {
        if options & !127 != 0 {
            return Err(Error::UnsupportedOption);
        }
        Ok(Self { options })
    }
    pub fn sort_key(&self, input: &[u8]) -> Result<Vec<u8>, Error> {
        core::sort_key(input, self.options)
    }
    pub fn compare(&self, a: &[u8], b: &[u8]) -> Result<std::cmp::Ordering, Error> {
        if self.options & 1 != 0 {
            return Ok(a.cmp(b));
        }
        Ok(self.sort_key(a)?.cmp(&self.sort_key(b)?))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn binary_code_point_key() {
        assert_eq!(
            Collator::new(1).and_then(|c| c.sort_key(b"a\0\xff")),
            Ok(b"a\0\xff\0".to_vec())
        );
    }
}
