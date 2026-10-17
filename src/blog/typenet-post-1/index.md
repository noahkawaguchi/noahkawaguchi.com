# Encoding TCP in Rust's Type System, Part 1: A Sequence Number Is Not a `u32`

<br />

In this post, I'll discuss one example of how I used Rust's type system to enforce correctness while implementing TCP/IP in my project [Typenet](https://github.com/noahkawaguchi/typenet).

Although the properties of TCP sequence numbers are a rather specific detail within the context of the larger TCP/IP stack I built, they are one of the main driving forces behind TCP's guarantees. I'll focus on them here as a digestible microcosm of how using Rust's type system has helped me align concrete implementations with abstract concepts and make incorrect states unrepresentable throughout the project. After a brief explanation of the problem, I'll go level by level through increasingly type-safe designs.

## Table of Contents

1. [The Problem at Hand](#the-problem-at-hand)
2. [Level 0: `u32`](#level-0-u32)
3. [Level 0.5: `u32` and `SeqCmp` Trait](#level-05-u32-and-seqcmp-trait)
4. [Level 1: `Wrapping<u32>`](#level-1-wrappingu32)
5. [Level 2: `Seq` Type](#level-2-seq-type)
6. [Level 3: `SeqPoint` and `SeqOffset`](#level-3-seqpoint-and-seqoffset)
7. [Level 4: `SeqPoint<In>`, `SeqPoint<Out>`, `SeqOffset<In>`, and `SeqOffset<Out>`](#level-4-seqpointin-seqpointout-seqoffsetin-and-seqoffsetout)
8. [Conclusion](#conclusion)

## The Problem at Hand

For TCP to be reliable, each side of the connection needs to keep track of each byte sent and received. This starts when each side generates an initial sequence number (ISN). Each side then maintains a set of state variables, some of which are based on their own ISN, and others of which are based on the peer's ISN.

These sequence numbers are 32 bits wide, are unsigned, and use [serial number arithmetic](https://datatracker.ietf.org/doc/html/rfc1982), where the range of representable values wraps around in a circle. This means that in addition to using wrapping arithmetic (`0xFFFF_FFFF + 1 == 0`), inequalities are not the plain linear ones provided as `<` and `<=` in programming languages. Instead, for a bit width of 32, a number more than `1 << 31` greater than another is considered less than it (`0xFFFF_FFFF < 0`). In other words, considering wrapping in both directions, `a < b` if it's closer to get from `a` to `b` in the positive direction, and conversely, `a > b` if it's closer to get from `a` to `b` in the negative direction. Exactly `1 << 31` apart (antipodes) is left up to the implementation and should never be encountered in real-world TCP.

## Level 0: `u32`

My initial approach was to represent sequence numbers using the plain unsigned 32-bit integer type, or in Rust terms, `u32`. I used Rust's `wrapping_add` and `wrapping_sub` methods for arithmetic and defined a free function for circular comparison.[^1]

> [!TIP]
> Press play on any code block to run it!

```rust
fn precedes(a: u32, b: u32) -> bool { a.wrapping_sub(b) >= 1 << 31 }

assert!(precedes(u32::MAX, u32::MIN));
assert!(!precedes(u32::MIN, u32::MAX));
assert_eq!(u32::MAX.wrapping_add(1), u32::MIN);

println!("Assertions passed!");
```

## Level 0.5: `u32` and `SeqCmp` Trait

This doesn't quite warrant a full level up since it's more of a cosmetic difference, but switching to a trait instead of a free function allowed the method name to sit between its operands, reading much more naturally.

```rust
trait SeqCmp {
    fn precedes(self, other: Self) -> bool;
}

impl SeqCmp for u32 {
    fn precedes(self, other: Self) -> bool { self.wrapping_sub(other) >= 1 << 31 }
}

assert!(u32::MAX.precedes(u32::MIN));
assert!(!u32::MIN.precedes(u32::MAX));
assert_eq!(u32::MAX.wrapping_add(1), u32::MIN);

println!("Assertions passed!");
```

However, I was still just calling methods on primitive `u32` values. `u32` was really a stand-in for TCP sequence numbers, which have completely different properties.

## Level 1: `Wrapping<u32>`

The next simplest step was to use Rust's `Wrapping<T>`, which just replaces the implementations of regular arithmetic operators like `+` with their `wrapping_*` equivalents.

```rust
use std::num::Wrapping;

trait SeqCmp {
    fn precedes(self, other: Self) -> bool;
}

impl SeqCmp for Wrapping<u32> {
    fn precedes(self, other: Self) -> bool { self - other >= Self(1 << 31) }
}

let [min, max] = [Wrapping(u32::MIN), Wrapping(u32::MAX)];

assert!(max.precedes(min));
assert!(!min.precedes(max));
assert_eq!(max + Wrapping(1), min);

println!("Assertions passed!");
```

Although this made the wrapping arithmetic built in, comparison still used the trait and was not any better than plain `u32`. More broadly, `Wrapping<u32>` is just not what a TCP sequence number _is_.

```rust
use std::num::Wrapping;

let seq_num_read_off_the_wire = Wrapping(42u32);
let round_robin_counter = Wrapping(42u32);

if seq_num_read_off_the_wire == round_robin_counter {
    println!("Semantically incomparable values found equal");
}
```

Since `Wrapping<u32>` is as much a round robin counter or anything else that wraps as it is a TCP sequence number, the next step was to remove functionality that sequence numbers shouldn't have, which can be done with a [newtype](https://doc.rust-lang.org/rust-by-example/generics/new_types.html).

## Level 2: `Seq` Type

One key example of why a sequence number is not `Wrapping<u32>` is that plain inequalities like `<` are defined for `Wrapping<u32>` and not for sequence numbers, as noted above. Accordingly, my next step was wrapping `Wrapping<u32>` in my own type, `Seq`, after which plain `<` no longer compiled.

> [!NOTE]
> The examples in this post don't show visibility information, but in the codebase, the inner types are private so the wrappers' invariants are actually enforced.

```rust
use std::{num::Wrapping, ops::Add};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Seq(Wrapping<u32>);

impl Seq {
    fn new(primitive: u32) -> Self { Self(Wrapping(primitive)) }

    fn precedes(self, other: Self) -> bool { self.0 - other.0 >= Wrapping(1 << 31) }
}

impl Add for Seq {
    type Output = Self;

    fn add(self, rhs: Self) -> Self::Output { Self(self.0 + rhs.0) }
}

let [min, max] = [Seq::new(u32::MIN), Seq::new(u32::MAX)];

assert!(max.precedes(min));
assert!(!min.precedes(max));
assert_eq!(max + Seq::new(1), min);

println!("Assertions passed!");
```

At first, I was excited to make `<` use `precedes` like `Wrapping<T>` makes `+` use `wrapping_add`, which would mean implementing `PartialOrd` (partial order) and/or `Ord` (total order) for the type. Implementing `Ord`, for example, would allow `Seq` to be used for the keys of a `BTreeMap` when reassembling segments that arrived out of order. However, this would be incorrect because the docs for both [`PartialOrd`](https://doc.rust-lang.org/std/cmp/trait.PartialOrd.html) and [`Ord`](https://doc.rust-lang.org/std/cmp/trait.Ord.html) state transitivity requirements (`a < b` and `b < c` must imply `a < c`).

It is arguably pragmatic to implement only `PartialOrd` anyway, [as smoltcp does](https://github.com/smoltcp-rs/smoltcp/blob/87b463f50c15f30e4cd2e2725a3bcd5cb883e4d9/src/wire/tcp.rs#L79), since `<` and friends would still be correct for pairs of sequence numbers with the relatively small offsets expected in real TCP. Still, since this technically violates both the transitivity and duality (`a < b` if and only if `b > a`) requirements in the `PartialOrd` docs, I decided to stick with `a.precedes(b)`.

There was a clear issue with the `Seq` implementation, though. A clock is a useful model here because its hours wrap around just like sequence space. Points in time and offsets between them are two distinct types with very different properties. Since `Seq` made no distinction, it allowed invalid operations akin to 3 o'clock + 5 o'clock.

| operation             | result                                                           |
| --------------------- | ---------------------------------------------------------------- |
| 3 o'clock + 5 hours   | 8 o'clock                                                        |
| 3 hours + 5 hours     | 8 hours                                                          |
| 3 o'clock + 5 o'clock | nonsense                                                         |
| 3 hours + 5 o'clock   | not defined (write it as 5 o'clock + 3 hours instead)            |
| 3 o'clock - 5 hours   | 10 o'clock                                                       |
| 3 hours - 5 hours     | -2 hours (negative meaning an offset of 2 hours earlier in time) |
| 3 o'clock - 5 o'clock | -2 hours (negative meaning 3 o'clock is earlier than 5 o'clock)  |
| 3 hours - 5 o'clock   | nonsense                                                         |

In Rust terms, the two types at play here are similar to `std::time::Instant` and `std::time::Duration`, except that `Duration` uses an unsigned representation, while offsets between two times on a clock are signed (earlier or later). The difference between two `Instant`s really is conceptually signed, but the standard library's implementation saturates at zero or returns `None` rather than returning a negative `Duration`.

## Level 3: `SeqPoint` and `SeqOffset`

Accordingly, I split `Seq` into `SeqPoint` and `SeqOffset`, defining only the operations between them that should really be defined. I had initially used the name `SeqDist` instead of `SeqOffset`, but that was actually incorrect. A distance is symmetric and non-negative, while an offset or displacement is signed and directional. For example, the physical distance between Tokyo and New York is 6,740 miles in either direction, but the time difference between them (when New York isn't on daylight saving time) is either -14 hours or +14 hours depending on which direction you measure from.

The code was then able to mirror the table of clock operations above.[^2] As an added bonus, the sign of the offset could be used in the `precedes` implementation to slightly deduplicate logic and ensure the two wouldn't fall out of step.

```rust
{{#rustdoc_include ../../../listings/typenet-post-1/level_3.rs}}

let [min, max] = [SeqPoint::new(u32::MIN), SeqPoint::new(u32::MAX)];

assert!(max.precedes(min));
assert!(!min.precedes(max));

// 3 o'clock + 5 hours
assert_eq!(max + SeqOffset::new(1), min);
// 3 hours + 5 hours
assert_eq!(SeqOffset::new(1) + SeqOffset::new(2), SeqOffset::new(3));
// 3 o'clock - 5 hours
assert_eq!(min - SeqOffset::new(1), max);
// 3 hours - 5 hours
assert_eq!(SeqOffset::new(2) - SeqOffset::new(3), SeqOffset::new(-1));
// 3 o'clock - 5 o'clock
assert_eq!(max - min, SeqOffset::new(-1));

println!("Assertions passed!");
```

With that change, the invalid operations no longer compiled.

```rust,compile_fail
{{#rustdoc_include ../../../listings/typenet-post-1/level_3.rs:9999}}
#
// 3 o'clock + 5 o'clock
let nonsense1 = SeqPoint::new(1) + SeqPoint::new(2);
// 3 hours + 5 o'clock
let wrong_operand_order = SeqOffset::new(1) + SeqPoint::new(2);
// 3 hours - 5 o'clock
let nonsense2 = SeqOffset::new(1) - SeqPoint::new(2);
```

However, there was still a hole in the `SeqPoint` and `SeqOffset` model. First, some definitions from [RFC 9293, Section 3.4](https://datatracker.ietf.org/doc/html/rfc9293#section-3.4):

- `SND.NXT`: next sequence number to be sent
- `RCV.NXT`: next sequence number expected on an incoming segment
- `SND.UNA`: oldest unacknowledged sequence number

When determining the number of bytes sent but not yet acknowledged by the peer, the value to be calculated is the offset of `SND.NXT` past `SND.UNA`. In the `SeqPoint`/`SeqOffset` model, all three of the variables above were represented using `SeqPoint`, so `RCV.NXT` could easily be used in place of `SND.NXT` or `SND.UNA`, producing nonsense.

```rust
{{#rustdoc_include ../../../listings/typenet-post-1/level_3.rs:9999}}
#
struct ConnState {
    snd_nxt: SeqPoint,
    rcv_nxt: SeqPoint,
    snd_una: SeqPoint,
    /* Other fields */
}

let conn = ConnState {
    snd_nxt: SeqPoint::new(7),
    rcv_nxt: SeqPoint::new(3),
    snd_una: SeqPoint::new(1),
};

let sent_but_not_acked = conn.snd_nxt - conn.snd_una;
assert_eq!(sent_but_not_acked, SeqOffset::new(6));

let nonsense = conn.rcv_nxt - conn.snd_una;
assert_eq!(nonsense, SeqOffset::new(2));

println!("Assertions passed (including the nonsense one)!");
```

Although this kind of bug might seem like a logic error, it was really a type error, just represented as a logic error under this model. Since the two opposing streams of TCP sequence numbers originate from independently generated ISNs and have no numerical bearing on each other's values, this is one more dimension by which these values are of different types.

## Level 4: `SeqPoint<In>`, `SeqPoint<Out>`, `SeqOffset<In>`, and `SeqOffset<Out>`

Unlike the split into `SeqPoint` and `SeqOffset`, which was about types that behave differently but interact with each other in specific ways, the split into `In` (incoming/inbound) and `Out` (outgoing/outbound) was about types that mirror each other but never interact at all. This can be enforced at compile time with a [phantom type parameter](https://doc.rust-lang.org/rust-by-example/generics/phantom.html) used as a marker.

> [!NOTE]
> Everything is in one module here, but in the codebase, the `Direction` trait is [sealed](https://rust-lang.github.io/api-guidelines/future-proofing.html#sealed-traits-protect-against-downstream-implementations-c-sealed), ensuring that using it as a bound means exactly `In` or `Out`.

```rust
{{#rustdoc_include ../../../listings/typenet-post-1/level_4.rs}}

// The compiler infers here that the second `SeqPoint` must also be `Out` since arrays
// must contain only one type
let [min, max] = [SeqPoint::<Out>::new(u32::MIN), SeqPoint::new(u32::MAX)];

assert!(max.precedes(min));
assert!(!min.precedes(max));

assert_eq!(max + SeqOffset::new(1), min);
assert_eq!(SeqOffset::<In>::new(1) + SeqOffset::new(2), SeqOffset::new(3));

println!("Assertions passed!");
```

Attempting to operate on two values from opposing streams then failed to compile.

```rust,compile_fail
{{#rustdoc_include ../../../listings/typenet-post-1/level_4.rs:9999}}
#
let nonsense1 = SeqPoint::<Out>::new(1) + SeqOffset::<In>::new(2);
let nonsense2 = SeqOffset::<In>::new(1) + SeqOffset::<Out>::new(2);
```

This was similar to the Level 3 `SeqPoint` and `SeqOffset` implementation, except it added a restriction that operations like the addition shown here were only defined when the type parameter `D` was the same between the two operands. This created a static guarantee that, for example, `RCV.NXT` could not be used in place of `SND.NXT` or `SND.UNA`.

```rust
{{#rustdoc_include ../../../listings/typenet-post-1/level_4.rs:9999}}
#
struct ConnState {
    snd_nxt: SeqPoint<Out>,
    rcv_nxt: SeqPoint<In>,
    snd_una: SeqPoint<Out>,
    /* Other fields */
}

let conn = ConnState {
    snd_nxt: SeqPoint::new(7),
    rcv_nxt: SeqPoint::new(3),
    snd_una: SeqPoint::new(1),
};

let sent_but_not_acked = conn.snd_nxt - conn.snd_una;
assert_eq!(sent_but_not_acked, SeqOffset::new(6));

println!("Assertions passed!");
```

The same misuse of `ConnState` fields from before then failed to compile.

```rust,compile_fail
{{#rustdoc_include ../../../listings/typenet-post-1/level_4.rs:9999}}
#
# struct ConnState {
#     snd_nxt: SeqPoint<Out>,
#     rcv_nxt: SeqPoint<In>,
#     snd_una: SeqPoint<Out>,
#     /* Other fields */
# }
#
# let conn = ConnState {
#     snd_nxt: SeqPoint::new(7),
#     rcv_nxt: SeqPoint::new(3),
#     snd_una: SeqPoint::new(1),
# };
#
let nonsense = conn.rcv_nxt - conn.snd_una;
```

`In`, `Out`, and `Direction` have a bit more going on in the codebase, and I have many other uses for them besides sequence numbers, but I'll save that for another post.

## Conclusion

Each level traded a bit of convenience for stronger guarantees. The more customized the types became, the more of their implementations had to be written by hand, with each operator getting one or more `impl` blocks. Nevertheless, I think this was a net positive. Having to be explicit about the exact operations that should be possible eliminated many potential misuses of plain types like `u32`.

The approach is also not completely foolproof. There are still some incorrect operations that even Level 4 would not catch at compile time, such as `conn.snd_una - conn.snd_nxt` (though this would at least correctly trigger an error case in the surrounding code at runtime). Going further to encode rules like this in the type system is one potential next step.

The biggest thing I learned in this part of the project is that just because something is 32 bits on the wire with no concept of negative, and the programming language happens to provide a `u32` type, that doesn't mean it's a `u32`. In other words, a type is not only what something is made up of, but also what one can and cannot do with it. If two values support different operations, or can be combined with different things, they are different types, even if they are both represented with 32 bits.

<br />

[^1]: In the project, I initially used the name `seq_lt` and switched to `precedes` partway through. For consistency, I use `precedes` throughout this post.

[^2]: The codebase implements only the subset of valid operations that are actually used. Additionally, the examples here use concrete `i32` inside `SeqOffset` for simplicity, while the codebase uses generics. This is because some offsets are naturally unsigned, such as window sizes and payload lengths.
