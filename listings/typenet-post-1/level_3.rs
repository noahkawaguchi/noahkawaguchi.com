use std::{
    num::Wrapping,
    ops::{Add, Sub},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct SeqPoint(Wrapping<u32>);

impl SeqPoint {
    fn new(primitive: u32) -> Self { Self(Wrapping(primitive)) }

    fn precedes(self, other: Self) -> bool { (self - other).0.0 < 0 }
}

// 3 o'clock - 5 o'clock
impl Sub for SeqPoint {
    type Output = SeqOffset;

    fn sub(self, rhs: Self) -> Self::Output {
        SeqOffset::new((self.0 - rhs.0).0.cast_signed())
    }
}

// 3 o'clock + 5 hours
impl Add<SeqOffset> for SeqPoint {
    type Output = Self;

    fn add(self, rhs: SeqOffset) -> Self::Output {
        Self(self.0 + Wrapping(rhs.0.0.cast_unsigned()))
    }
}

// 3 o'clock - 5 hours
impl Sub<SeqOffset> for SeqPoint {
    type Output = Self;

    fn sub(self, rhs: SeqOffset) -> Self::Output {
        Self(self.0 - Wrapping(rhs.0.0.cast_unsigned()))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct SeqOffset(Wrapping<i32>);

impl SeqOffset {
    fn new(primitive: i32) -> Self { Self(Wrapping(primitive)) }
}

// 3 hours + 5 hours
impl Add for SeqOffset {
    type Output = Self;

    fn add(self, rhs: Self) -> Self::Output { Self(self.0 + rhs.0) }
}

// 3 hours - 5 hours
impl Sub for SeqOffset {
    type Output = Self;

    fn sub(self, rhs: Self) -> Self::Output { Self(self.0 - rhs.0) }
}
