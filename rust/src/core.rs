//! Pure, fallibly allocated key builder. The packaged Zig implementation is
//! the reference for both key bytes and malformed-input behavior.
use crate::{Error, tables};
use tables::{
    WB_A_LETTER, WB_EXTEND, WB_EXTEND_NUM_LET, WB_FORMAT, WB_HEBREW_LETTER, WB_MID_LETTER,
    WB_MID_NUM_LET, WB_NUMERIC, WB_OTHER, WB_SINGLE_QUOTE, WB_ZWJ,
};
type Result<T> = std::result::Result<T, Error>;

#[derive(Default)]
struct Bytes(Vec<u8>);
impl Bytes {
    fn push(&mut self, byte: u8) -> Result<()> {
        self.0.try_reserve(1).map_err(|_| Error::OutOfMemory)?;
        self.0.push(byte);
        Ok(())
    }
    fn extend(&mut self, bytes: &[u8]) -> Result<()> {
        self.0
            .try_reserve(bytes.len())
            .map_err(|_| Error::OutOfMemory)?;
        self.0.extend_from_slice(bytes);
        Ok(())
    }
}

fn decode(s: &[u8], i: usize) -> Option<(u32, usize)> {
    let b = *s.get(i)?;
    if b < 128 {
        return Some((b as u32, 1));
    }
    let width = match b {
        0xc2..=0xdf => 2,
        0xe0..=0xef => 3,
        0xf0..=0xf4 => 4,
        _ => return None,
    };
    let text = std::str::from_utf8(s.get(i..i + width)?).ok()?;
    Some((text.chars().next()? as u32, width))
}
fn digit(s: &[u8], i: usize) -> Option<(u8, usize)> {
    let b = *s.get(i)?;
    if b.is_ascii_digit() {
        return Some((b - b'0', 1));
    }
    if b < 128 {
        return None;
    }
    let (cp, n) = decode(s, i)?;
    match cp {
        0xff10..=0xff19 => Some(((cp - 0xff10) as u8, n)),
        0x1d7ce..=0x1d7ff => Some((((cp - 0x1d7ce) % 10) as u8, n)),
        _ => None,
    }
}
fn folded(cp: u32) -> Option<(u8, u8, bool)> {
    if (b'a' as u32..=b'z' as u32).contains(&cp) {
        return Some((cp as u8, 0, false));
    }
    if (b'A' as u32..=b'Z' as u32).contains(&cp) {
        return Some((cp as u8 + 32, 0, true));
    }
    tables::FOLDS
        .binary_search_by_key(&cp, |t| t.0)
        .ok()
        .map(|i| {
            let (_, base, dia, upper) = tables::FOLDS[i];
            (base, dia, upper)
        })
}
fn expansion(cp: u32) -> Option<&'static [u8]> {
    tables::EXPANSIONS
        .binary_search_by_key(&cp, |t| t.0)
        .ok()
        .map(|i| tables::EXPANSIONS[i].1)
}
fn punctuation(cp: u32) -> bool {
    let pos = tables::PUNCTUATION.partition_point(|r| r.0 <= cp);
    pos > 0 && cp <= tables::PUNCTUATION[pos - 1].1
}
fn word(s: &[u8], i: usize) -> (u8, usize) {
    let Some((cp, n)) = decode(s, i) else {
        return (WB_OTHER, i + 1);
    };
    let pos = tables::WORD_RANGES.partition_point(|t| t.0 <= cp);
    if pos > 0 && cp <= tables::WORD_RANGES[pos - 1].1 {
        (tables::WORD_RANGES[pos - 1].2, i + n)
    } else {
        (WB_OTHER, i + n)
    }
}
fn previous(s: &[u8], end: usize) -> (u8, usize) {
    let mut i = end - 1;
    while i > 0 && s[i] & 0xc0 == 0x80 {
        i -= 1;
    }
    let (p, next) = word(s, i);
    if next == end {
        (p, i)
    } else {
        (WB_OTHER, end - 1)
    }
}
fn ignored(p: u8) -> bool {
    matches!(p, WB_EXTEND | WB_FORMAT | WB_ZWJ)
}
fn ah(p: u8) -> bool {
    matches!(p, WB_A_LETTER | WB_HEBREW_LETTER)
}
fn mid(p: u8) -> bool {
    matches!(p, WB_MID_LETTER | WB_MID_NUM_LET | WB_SINGLE_QUOTE)
}
fn prev_sig(s: &[u8], mut end: usize) -> Option<(u8, usize)> {
    while end > 0 {
        let (p, i) = previous(s, end);
        end = i;
        if !ignored(p) {
            return Some((p, i));
        }
    }
    None
}
fn boundary_before(s: &[u8], i: usize) -> bool {
    if i == 0 {
        return true;
    }
    let (mut p, mut start) = previous(s, i);
    if ignored(p) {
        match prev_sig(s, start) {
            Some(t) => {
                p = t.0;
                start = t.1;
            }
            None => return true,
        }
    }
    if ah(p) || matches!(p, WB_EXTEND_NUM_LET | WB_NUMERIC) {
        return false;
    }
    if mid(p) && prev_sig(s, start).is_some_and(|t| ah(t.0)) {
        return false;
    }
    true
}
fn boundary_after(s: &[u8], i: usize) -> bool {
    if i == s.len() {
        return true;
    }
    let (p, mut next) = word(s, i);
    if ignored(p) || ah(p) || matches!(p, WB_EXTEND_NUM_LET | WB_NUMERIC) {
        return false;
    }
    if mid(p) {
        while next < s.len() {
            let (q, end) = word(s, next);
            next = end;
            if !ignored(q) {
                return !ah(q);
            }
        }
    }
    true
}
const ROMAN: &[(u16, &[u8])] = &[
    (1000, b"M"),
    (900, b"CM"),
    (500, b"D"),
    (400, b"CD"),
    (100, b"C"),
    (90, b"XC"),
    (50, b"L"),
    (40, b"XL"),
    (10, b"X"),
    (9, b"IX"),
    (5, b"V"),
    (4, b"IV"),
    (1, b"I"),
];
fn roman(s: &[u8]) -> Option<u16> {
    if s.is_empty() || s.len() > 15 {
        return None;
    }
    let mut upper = [0u8; 15];
    let mut lower_seen = false;
    let mut upper_seen = false;
    for (i, &b) in s.iter().enumerate() {
        let c = b.to_ascii_uppercase();
        if !b"IVXLCDM".contains(&c) {
            return None;
        }
        lower_seen |= b.is_ascii_lowercase();
        upper_seen |= b.is_ascii_uppercase();
        upper[i] = c;
    }
    if lower_seen && upper_seen {
        return None;
    }
    let mut i = 0;
    let mut total = 0;
    while i < s.len() {
        let &(value, token) = ROMAN.iter().find(|t| upper[i..s.len()].starts_with(t.1))?;
        total += value;
        i += token.len();
    }
    let mut remaining = total;
    let mut i = 0;
    for &(value, token) in ROMAN {
        while remaining >= value {
            if !upper[i..s.len()].starts_with(token) {
                return None;
            }
            i += token.len();
            remaining -= value;
        }
    }
    (i == s.len()).then_some(total)
}
fn significant(d: &[u8]) -> &[u8] {
    &d[d.iter().position(|&v| v != 0).unwrap_or(d.len())..]
}
fn trimmed(d: &[u8]) -> &[u8] {
    &d[..d.iter().rposition(|&v| v != 0).map_or(0, |i| i + 1)]
}
fn digits(s: &[u8], start: usize) -> Result<(Bytes, usize, u8)> {
    let mut d = Bytes::default();
    let mut i = start;
    let mut style = 0;
    while let Some((v, n)) = digit(s, i) {
        d.push(v)?;
        i += n;
        style |= u8::from(n > 1);
    }
    Ok((d, i, style))
}
fn group_sep(s: &[u8], i: usize, comma: bool) -> usize {
    match s[i] {
        b' ' | b'\'' | b'_' => 1,
        b',' if !comma => 1,
        b'.' if comma => 1,
        _ => match decode(s, i) {
            Some((0xa0 | 0x2009 | 0x202f, n)) => n,
            _ => 0,
        },
    }
}
fn grouped(s: &[u8], start: usize, comma: bool, absorb: bool) -> Result<(Bytes, Bytes, usize)> {
    let mut int = Bytes::default();
    let mut frac = Bytes::default();
    let mut i = start;
    while i < s.len() {
        if let Some((v, n)) = digit(s, i) {
            int.push(v)?;
            i += n;
            continue;
        }
        let n = if absorb { group_sep(s, i, comma) } else { 0 };
        if n == 0 || digit(s, i + n).is_none() {
            break;
        }
        i += n;
    }
    if s.get(i) == Some(&if comma { b',' } else { b'.' }) && digit(s, i + 1).is_some() {
        let (d, end, _) = digits(s, i + 1)?;
        frac = d;
        i = end;
        frac.0.truncate(trimmed(&frac.0).len());
    }
    Ok((int, frac, i))
}
fn exponent(s: &[u8], start: usize) -> Result<Option<(Bytes, bool, usize)>> {
    if !s.get(start).is_some_and(|b| matches!(b, b'e' | b'E')) {
        return Ok(None);
    }
    let mut i = start + 1;
    let neg = s.get(i) == Some(&b'-');
    if s.get(i).is_some_and(|b| matches!(b, b'+' | b'-')) {
        i += 1;
    }
    let (d, end, _) = digits(s, i)?;
    Ok((!d.0.is_empty()).then_some((d, neg, end)))
}
/// Add a bounded mantissa offset to an arbitrary-width signed exponent.
fn adjust(digits: &[u8], negative: bool, offset: i128) -> Result<(bool, Bytes)> {
    let a = significant(digits);
    let negative = negative && !a.is_empty();
    let mut stack = [0u8; 40];
    let mut n = 0;
    let mut v = offset.unsigned_abs();
    while v > 0 {
        stack[n] = (v % 10) as u8;
        n += 1;
        v /= 10;
    }
    stack[..n].reverse();
    let b = &stack[..n];
    let b_neg = offset < 0;
    let mut result = Bytes::default();
    let mut sign = negative;
    if negative == b_neg {
        let (mut ia, mut ib, mut carry) = (a.len(), b.len(), 0u8);
        while ia > 0 || ib > 0 || carry > 0 {
            let mut sum = carry;
            if ia > 0 {
                ia -= 1;
                sum += a[ia];
            }
            if ib > 0 {
                ib -= 1;
                sum += b[ib];
            }
            result.push(sum % 10)?;
            carry = sum / 10;
        }
    } else {
        let smaller = a.len().cmp(&b.len()).then_with(|| a.cmp(b)).is_lt();
        let (large, small) = if smaller { (b, a) } else { (a, b) };
        if smaller {
            sign = b_neg;
        }
        let (mut ia, mut ib, mut borrow) = (large.len(), small.len(), 0i16);
        while ia > 0 {
            ia -= 1;
            let mut value = large[ia] as i16 - borrow;
            if ib > 0 {
                ib -= 1;
                value -= small[ib] as i16;
            }
            borrow = i16::from(value < 0);
            if value < 0 {
                value += 10;
            }
            result.push(value as u8)?;
        }
    }
    while result.0.last() == Some(&0) {
        result.0.pop();
    }
    result.0.reverse();
    if result.0.is_empty() {
        sign = false;
    }
    Ok((sign, result))
}

#[derive(Default)]
struct Levels {
    p: Bytes,
    s: Bytes,
    t: Bytes,
}
impl Levels {
    fn weights(&mut self, secondary: u8, tertiary: u8) -> Result<()> {
        self.s.push(secondary)?;
        self.t.push(tertiary)
    }
    fn length(&mut self, mut n: usize, inverted: bool) -> Result<()> {
        if n <= 250 {
            return self
                .p
                .push(if inverted { 254 - n as u8 } else { 2 + n as u8 });
        }
        let mut tmp = [0u8; 16];
        let mut len = 0;
        while n > 0 {
            tmp[len] = (n % 254) as u8;
            n /= 254;
            len += 1;
        }
        self.p.push(if inverted { 2 } else { 255 })?;
        self.p.push(if inverted {
            254 - len as u8
        } else {
            2 + len as u8
        })?;
        for &v in tmp[..len].iter().rev() {
            self.p.push(if inverted { 255 - v } else { 2 + v })?;
        }
        Ok(())
    }
    fn emit_digits(&mut self, d: &[u8], neg: bool) -> Result<()> {
        for &v in d {
            self.p.push(if neg { 11 - v } else { 2 + v })?;
        }
        Ok(())
    }
    fn integer(&mut self, d: &[u8], neg: bool, style: u8, zero_weight: u8) -> Result<()> {
        let sig = significant(d);
        self.p.push(if neg { 0x28 } else { 0x30 })?;
        self.length(sig.len(), neg)?;
        self.emit_digits(sig, neg)?;
        if neg {
            self.p.push(255)?;
        }
        self.weights(2 + style, zero_weight)
    }
    fn numeric(
        &mut self,
        int: &[u8],
        frac: &[u8],
        exp: Option<(&[u8], bool)>,
        sci: bool,
        neg: bool,
    ) -> Result<()> {
        let sig = significant(int);
        self.p.push(if neg { 0x28 } else { 0x30 })?;
        if !sci {
            self.length(sig.len(), neg)?;
            self.emit_digits(sig, neg)?;
            self.emit_digits(frac, neg)?;
        } else {
            let fraction = if sig.is_empty() {
                significant(frac)
            } else {
                frac
            };
            let zero = sig.is_empty() && fraction.is_empty();
            self.p.push(if zero || neg { 2 } else { 3 })?;
            if !zero {
                let offset = if !sig.is_empty() {
                    sig.len() as i128 - 1
                } else {
                    -((frac.len() - fraction.len()) as i128) - 1
                };
                let (d, sign) = exp.unwrap_or((&[], false));
                let (sign, d) = adjust(d, sign, offset)?;
                let flip = sign != neg;
                self.p.push(if flip { 2 } else { 3 })?;
                self.length(d.0.len(), flip)?;
                self.emit_digits(&d.0, flip)?;
                self.emit_digits(
                    if fraction.is_empty() {
                        trimmed(sig)
                    } else {
                        sig
                    },
                    neg,
                )?;
                self.emit_digits(fraction, neg)?;
            }
        }
        if neg {
            self.p.push(255)?;
        }
        self.weights(2, 2)
    }
    fn letter(&mut self, base: u8, dia: u8, upper: bool, expanded: bool) -> Result<()> {
        let mut rank = base - b'a';
        for (b, extra) in [(b'a', 2), (b'i', 1), (b'n', 1), (b's', 1), (b't', 1)] {
            if base > b {
                rank += extra;
            }
        }
        rank += match (base, dia) {
            (b'a', 12) => 1,
            (b'a', 3) => 2,
            (b'i', 3) | (b'n', 4) | (b's' | b't', 13) => 1,
            _ => 0,
        };
        self.p.extend(&[0x40, 2 + rank])?;
        self.weights(
            2 + dia,
            if expanded {
                4 + u8::from(upper)
            } else {
                2 + u8::from(upper)
            },
        )
    }
    fn other(&mut self, cp: u32) -> Result<()> {
        self.p.extend(&[
            0x50,
            2 + (cp / (253 * 253)) as u8,
            2 + ((cp % (253 * 253)) / 253) as u8,
            2 + (cp % 253) as u8,
        ])?;
        self.weights(2, 2)
    }
    fn roman(&mut self, value: u16) -> Result<()> {
        let mut v = value;
        let mut d = [0u8; 5];
        let mut n = 0;
        while v > 0 {
            d[n] = (v % 10) as u8;
            v /= 10;
            n += 1;
        }
        d[..n].reverse();
        self.integer(&d[..n], false, 2, 252)
    }
    fn expansion(&mut self, s: &[u8], use_roman: bool) -> Result<()> {
        if let Some(v) = use_roman.then(|| roman(s)).flatten() {
            return self.roman(v);
        }
        let mut i = 0;
        while i < s.len() {
            if digit(s, i).is_some() {
                let (d, end, style) = digits(s, i)?;
                self.integer(&d.0, false, style, zero_weight(&d.0))?;
                i = end;
                continue;
            }
            let c = s[i];
            if let Some((base, dia, upper)) = folded(c as u32) {
                self.letter(base, dia, upper, true)?;
            } else {
                self.p.extend(&[0x20, c])?;
                self.weights(2, 6)?;
            }
            i += 1;
        }
        Ok(())
    }
    fn finish(mut self) -> Result<Vec<u8>> {
        self.p.push(1)?;
        self.p.extend(&self.s.0)?;
        self.p.push(1)?;
        self.p.extend(&self.t.0)?;
        self.p.push(0)?;
        Ok(self.p.0)
    }
}
fn zero_weight(d: &[u8]) -> u8 {
    252 - d.iter().take_while(|&&v| v == 0).count().min(250) as u8
}

pub(super) fn sort_key(s: &[u8], options: u32) -> Result<Vec<u8>> {
    if options & 1 != 0 {
        let mut key = Bytes::default();
        key.extend(s)?;
        key.push(0)?;
        return Ok(key.0);
    }
    let (decimal, sci, use_roman) = (
        options & (8 | 32) != 0,
        options & 32 != 0,
        options & 64 != 0,
    );
    let mut out = Levels::default();
    let mut i = 0;
    if !decimal && s.first() == Some(&b'-') && digit(s, 1).is_some() {
        let (d, end, _) = digits(s, 1)?;
        out.integer(&d.0, true, 0, zero_weight(&d.0))?;
        i = end;
    }
    while i < s.len() {
        let b = s[i];
        if decimal {
            let signed = i == 0 && digit(s, 1).is_some();
            let neg = signed && b == b'-';
            let pos = signed && b == b'+';
            if neg || pos || digit(s, i).is_some() {
                let (int, frac, end) = grouped(
                    s,
                    i + usize::from(neg || pos),
                    options & 16 != 0,
                    options & 8 != 0,
                )?;
                let ex = if sci { exponent(s, end)? } else { None };
                out.numeric(
                    &int.0,
                    &frac.0,
                    ex.as_ref().map(|t| (t.0.0.as_slice(), t.1)),
                    sci,
                    neg,
                )?;
                i = ex.map_or(end, |t| t.2);
                continue;
            }
        }
        if use_roman && b.is_ascii_alphabetic() {
            let mut end = i;
            while end < s.len() && s[end].is_ascii_alphabetic() {
                end += 1;
            }
            if let Some(v) = (boundary_before(s, i) && boundary_after(s, end))
                .then(|| roman(&s[i..end]))
                .flatten()
            {
                out.roman(v)?;
            } else {
                for &c in &s[i..end] {
                    out.letter(c.to_ascii_lowercase(), 0, c.is_ascii_uppercase(), false)?;
                }
            }
            i = end;
            continue;
        }
        if digit(s, i).is_some() {
            let (d, end, style) = digits(s, i)?;
            out.integer(&d.0, false, style, zero_weight(&d.0))?;
            i = end;
            continue;
        }
        let Some((cp, n)) = decode(s, i) else {
            out.other(b as u32)?;
            i += 1;
            continue;
        };
        if tables::is_space(cp) {
            out.p.push(0x10)?;
            out.weights(2, 2)?;
        } else if let Some((base, mut dia, upper)) = folded(cp) {
            let mut n = n;
            if matches!(base, b's' | b't')
                && dia == 0
                && let Some((0x326 | 0x327, m)) = decode(s, i + n)
            {
                dia = 13;
                n += m;
            }
            out.letter(base, dia, upper, false)?;
            i += n;
            continue;
        } else if let Some(rep) = expansion(cp) {
            out.expansion(rep, use_roman)?;
        } else if (cp < 128 && b > 32) || punctuation(cp) {
            out.p.push(0x20)?;
            if cp < 128 {
                out.p.push(b)?;
            } else {
                out.p.extend(&[
                    0xff,
                    2 + (cp / (253 * 253)) as u8,
                    2 + ((cp % (253 * 253)) / 253) as u8,
                    2 + (cp % 253) as u8,
                ])?;
            }
            out.weights(2, 2)?;
        } else {
            out.other(cp)?;
        }
        i += n;
    }
    out.finish()
}
