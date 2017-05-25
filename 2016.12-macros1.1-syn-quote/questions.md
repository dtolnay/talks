**Question:** Is the `quote!` macro specific to Macros 1.1 or is it a general
string interpolation macro?

**Answer:** A bit of both. It is general in that Rust tokens go in and strings
come out, so there is no dependence on Macros 1.1 in that aspect. However it is
specific to manipulating Rust (or sufficiently Rust-like) source code. You
wouldn't use this to replace interpolation in a format string like `"Hello, {}"`
where the content is not Rust tokens. You also wouldn't use it for interpolation
of whitespace-sensitive Python source code.

---

**Question:** What, if any, checking does the `quote!` macro do before producing
its output? Does it check that you're going to be tokenizing valid Rust? Or does
it just go and emit tokens?

**Answer:** The `quote!` macro itself does no checking; the fragment of source
code that you write is the fragment of source code that you get.

There is some simple checking built in just by virtue of being an ordinary
macro, so in particular it isn't possible to invoke `quote!` with contents that
have mismatched parentheses or brackets or braces, or unclosed string literals.
There is no checking of syntax beyond that.

---

**Question:** If you, using `quote!`, produce invalid Rust source, what do the
downstream consumer's error messages look like?

**Answer:** There are three categories of invalid output that your macro might
emit:

- Syntax errors, meaning output that is not correctly structured Rust code. This
  is always a bug in the macro.
- Syntactically valid but otherwise incorrect output due to a bug in the macro.
- User errors, in which the user's code is wrong in a way that compounds into
  the macro output also being wrong. This can occur even in the absense of a bug
  in the macro.

A syntax error could be something like `quote! { impl HeapSize for #name; }`
which is syntactically not Rust code. The compiler's Rust parser cannot parse
this because there should be an impl body instead of `;`. The error message
points to the derive invocation in the user's code and looks like:

```
error: proc-macro derive produced unparseable tokens
 --> src/main.rs:4:10
  |
4 | #[derive(HeapSize)]
  |          ^^^^^^^^
```

An example of syntactically valid code that is otherwise incorrect is `quote! {
impl HeapSize for #name {} }` which is syntactically a Rust impl block but is
missing the `heap_size` method required by the `HeapSize` trait. Again the error
points to the derive invocation in the user's code, but the message is exactly
like what the user would see if they had handwritten the incorrect code
themselves:

```
error[E0046]: not all trait items implemented, missing: `heap_size`
 --> src/main.rs:4:10
  |
4 | #[derive(HeapSize)]
  |          ^^^^^^^^ missing `heap_size` in implementation
  |
  = note: `heap_size` from trait: `fn(&Self) -> usize`
```

Generally these first two categories are quickly caught by the macro author in
the course of unit-testing their macro. End users will not see such errors.

The third category is errors that compound out of the user's code being wrong,
without necessarily a bug in the macro. For example consider a user deriving
`HeapSize` for a `struct S { x: MyStruct }` in which `MyStruct` does not
implement `HeapSize`. The type-checking phase that figures out which traits are
implemented for which types happens well after macro expansion, so the macro may
correctly produce an output impl that just assumes it can invoke `HeapSize`
methods on each field. The error looks like:

```
error: no method named `heap_size` found for type `MyStruct` in the current scope
 --> src/main.rs:4:10
  |
4 | #[derive(HeapSize)]
  |          ^^^^^^^^
  |
  = help: items from traits can only be used if the trait is implemented and in
          scope; the following trait defines an item `heap_size`, perhaps you
          need to implement it:
  = help: candidate #1: `HeapSize`
```

Again the message is what the user would have gotten from handwriting the bad
impl themselves, but in this case the location of the error is misleading
because the derive macro is correctly implemented. Ideally we would want the
same error but pointing to the `MyStruct` field in the user's code. This is not
possible in the Macros 1.1 approach as it stands but work is underway to enable
more advanced error reporting in a future Macros 2.0 evolution.

---

**Question:** The internals of the `syn` crate looks very much like the parser
of rustc. Does it mirror the same data structures? Whenever there is an upgrade
on Rust, do you also try and reflect it on the `syn` crate as well?

**Answer:** Yes the rough structure of the compiler's syntax tree is mirrored in
`syn`.

The parser that exists in the Rust compiler is one of the most unstable pieces
of the compiler. The way we had been depending on that parser in the past was
through the `syntex` crate which essentially rips out the compiler's parser,
does some unholy things to make it compile independently of the rest of the
compiler codebase, and sticks it on crates.io with a rapidly growing version
number. The decisions and tradeoffs that motivate the design of the compiler's
parser are very different from what you would want in a library used by
thousands of procedural macros authors. In particular, the compiler wants to be
able to iterate quickly, make highly experimental changes, and optimize data
structures for efficient manipulation later in the compilation process.

In contrast, in a library used from procedural macros, stability is way more
important and performance is way less important. Frequent breaking changes in
`syntex` require coordinated upgrades across hundreds of downstream libraries.
And procedural macro performance is never worth worrying about because it is a
such a tiny part of total compile time. It is more important to optimize for
readability of code written against the data structures, rather than for
performance.

---

**Question:** What happens on the rare occasions when the Rust syntax changes?
This doesn't seem like it's an official part of the release of this feature, so
do you have a process for following Rust syntax changes?

**Answer:** The process is we will batch up breaking changes and make multiple
in the same major version of `syn`.

In the meantime what will happen is your procedural macro that you write against
`syn` will continue to work. It will continue to parse all the syntax that it
used to parse, and nothing breaks unless a user tries to use fancy new syntax
inside of a struct that they put a derive on. In that case the procedural macro
will return an error saying it failed to parse the thing. The macro author will
need to update to a newer version of `syn`.

This is a huge improvement over the past approach of libraries like Serde
depending directly on the compiler's `libsyntax` to interact with unstable macro
APIs. When Rust syntax changes necessitated breaking changes in the compiler's
data structures, what would happen is your code that compiled before would no
longer compile because now the data structures were different.

It is also a huge improvement over extracting `libsyntax` into a versioned
`syntex` crate and keeping it up to date with compiler changes, which is an
unbelievable time sink (I am one of the maintainers of `syntex`). The amount of
work that has gone into writing `syn` as a parser from scratch is less than the
amount of work that has gone into maintaining `syntex` in the same period of
time, probably by a factor of 3.

---

**Question:** What use cases do you envision people are going to build with
this? Other than the one example given in the talk.

**Answer:** [Serde] has been using this for the past couple months. Serde is a
serialization library that can derive implementations of traits for serializing
and deserializing data structures in a variety of formats. Another example is
[Diesel] which involves putting data structures into a database or taking them
out of a database. [Servo] uses it not just for the heap size use case but also
for tracing garbage collection as well as JavaScript reflectors.

[Serde]: https://serde.rs
[Diesel]: https://diesel.rs/
[Servo]: https://servo.org/

More generally, this is basically Rust's current substitute for runtime
reflection. If you think of some libraries or functionality built on runtime
reflection in other languages (let's say Java and Go because I know those the
best), most of those will instead in Rust be built on procedural macros. Data
serialization and database i/o are just examples of that.

In Java or Go if you want to serialize some data structure to JSON or
deserialize a data structure from JSON, it's going to be doing runtime
reflection. It will look at the type of your thing using reflection and decide
how to behave.

Macros 1.1 is a uniquely Rust-y alternative. Building the same functionality on
top of procedural macros means that you are forced to tell the compiler up
front, if this is the type of thing I see at runtime, here is how I plan to
behave. So all the same steps happen as if it were runtime reflection except
that most of them happen at compile time. We look at the type of the thing, we
decide how to behave. Then the compiler verifies that our plan for how to behave
is consistent with all of Rust's safety checks, and optimizes it to go fast at
runtime. The result is a system that is as flexible as runtime reflection for
most use cases, but also as safe as the rest of Rust and blazing fast.

---

**Question:** Going back to the heap size derive macro, at the end of the day it
looks like you're still calling a `heap_size` method on all of the field types.
This makes it look like if you are composing types, even the constituent types
still need to have a `heap_size` implementation. Is that just for the purposes
of a simple demo or am I completely misunderstanding at what point this code
hits the Rust compiler?

**Answer:** You would also put `#[derive(HeapSize)]` on the declaration of each
constituent type. In the example of the `Gradient` struct from the slides, there
would also need to be a derive on the `GradientKind` type. Then there would be
handwritten `HeapSize` implementations for things that cannot be derived, such
as for `bool` and `Vec<T>`.

---

**Question:** If there is an error that exists in the implementation of a trait
that you want to derive, where in the compilation process is the error message
for that going to show up?

**Answer:** It will give the user of the derive the same error message they
would have seen by handwriting the code emitted by the derive.

---

**Question:** Let's say I want to do something with a structure if it has three
members, or do something else if it has four members for example. What can you
do and what kind of decisions can you take at compile time?

**Answer:** The function that implements your procedural macro (the one that
takes in a `TokenStream` and returns a `TokenStream`) is an ordinary Rust
function. You can put whatever logic in there. In an extreme case you might look
at the input, make a database query based on it, and then produce an output of
source code. (Diesel actually does that! They have a mode where they will query
the database and get the table spec for a structure. It's awesome and scary.)

The syntax tree that you get back from parsing the input source code will
contain somewhere in it a vector of the fields. You can look at that and say `if
fields.len() == 3` then do this, else `if fields.len() == 4` then do something
else. What you are writing is Rust code.

As another example, your procedural macro may take into account attributes or
even doc comments to decide how to behave. Serde does this for allowing the user
to customize the serialized representation in certain ways.

This extreme flexibility is distinct from `macro_rules!` where you are very
limited in the sorts of logic that you can implement at compile time using them.

---

**Question:** Do the contents of the struct definition need to be 100% valid
Rust before they make it to your custom derive? Are you able to introduce your
own custom attributes within the derive?

**Answer:** The constraint is that your procedural macro is not allowed to
change the definition of the thing it was annotating. When something like
`#[derive(HeapSize)]` gets expanded it can add new source code to the crate but
it cannot change the definition of the struct it is applied to. That means the
struct definition has to be valid because it will also end up in your program
along with whatever the macro returned.

The one exception to this is that when you implement the procedural macro you
can have it tell the compiler to ignore attributes with a certain name. The
procedural macro can use those attributes to customize its behavior, after which
they get left in the source code but ignored by subsequent phases of
compilation.

Servo's implementation of the heap-size derive does this! They have an attribute 
that you can put on individual fields that says to leave this field out of the
heap size calculation.

---

**Question:** Can the procedural macro implementation pull in crates, and if so,
is there a way to keep the set of run-time crates separate from the set of
compile-time crates? Like if you wanted to use a dependency in your derive logic
that is required at compile time but you didn't necessarily want that to be in
your production code.

**Answer:** Yes we distinguish between those. The procedural macro is
effectively an executable that is being run by the compiler during compile time.
Dependencies of the procedural macro are not run-time dependencies of the
end-user's application.
