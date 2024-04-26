# Evil Json

A simple JSON decoding/encoding library.

State: Does work somewhat :)

## Goals
- Provide a JSON parser that can parse most\* JSON files (into a Value datatype provided by the library)
- Provide a nice and easy way to access values in a nested JSON Value
- Provide JSON encoder with some customizations (pretty printing)

\*: I am not planning to tailor this to any specific standard and I may ignore things like processing utf-8 etc.
