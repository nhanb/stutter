# stutter

is an HTML generator library in Zig using a LISP-like DSL and my excuse to practice writing a simple recursive descent parser. Here's a sample:

```
(doctype)
(html
  [:lang 'en']
  (head
    (meta [:charset "utf-8"])
    (title "Home"))
  (body
    (h1 [:class "foo" :id "bar"] "This is my home.")
    "free text"
    "more free text"))
```

**Do not use it**. Stutter is a work in progress that still lacks basic features:

- context-aware escaping
- variables
- conditionals
- loops

## Usage

To use it as a library, see the tests in **src/htmlgen.zig**.

There's also the main executable that reads the DSL from stdin and writes HTML to stdout. For example:

```sh
$ cat src/htmlgen_test_input.txt | zig build run
# <!DOCTYPE html>
# <html lang="en">
#   <head>
#     <meta charset="utf-8">
#     <title>
#       Home
#     </title>
#   </head>
#   <body>
#     <h1 class="foo" id="bar">
#       This is my home.
#     </h1>
#     free text
#     more free text
#   </body>
# </html>
```
