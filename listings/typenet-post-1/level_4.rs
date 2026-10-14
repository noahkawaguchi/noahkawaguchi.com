use std::{
    fmt::Debug,
    marker::PhantomData,
    num::Wrapping,
    ops::{Add, Sub},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct In;
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Out;

trait Direction: Debug + Clone + Copy + PartialEq + Eq {}
impl Direction for In {}
impl Direction for Out {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct SeqPoint<D: Direction> {
    wrapping: Wrapping<u32>,
    phantom: PhantomData<D>,
}

impl<D: Direction> SeqPoint<D> {
    fn new(primitive: u32) -> Self {
        Self { wrapping: Wrapping(primitive), phantom: PhantomData }
    }

    fn precedes(self, other: Self) -> bool { (self - other).wrapping.0 < 0 }
}

impl<D: Direction> Sub for SeqPoint<D> {
    type Output = SeqOffset<D>;

    fn sub(self, rhs: Self) -> Self::Output {
        SeqOffset::new((self.wrapping - rhs.wrapping).0.cast_signed())
    }
}

impl<D: Direction> Add<SeqOffset<D>> for SeqPoint<D> {
    type Output = Self;

    fn add(self, rhs: SeqOffset<D>) -> Self::Output {
        Self {
            wrapping: self.wrapping + Wrapping(rhs.wrapping.0.cast_unsigned()),
            phantom: PhantomData,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct SeqOffset<D: Direction> {
    wrapping: Wrapping<i32>,
    phantom: PhantomData<D>,
}

impl<D: Direction> SeqOffset<D> {
    fn new(primitive: i32) -> Self {
        Self { wrapping: Wrapping(primitive), phantom: PhantomData }
    }
}

impl<D: Direction> Add for SeqOffset<D> {
    type Output = Self;

    fn add(self, rhs: Self) -> Self::Output {
        Self { wrapping: self.wrapping + rhs.wrapping, phantom: PhantomData }
    }
}
