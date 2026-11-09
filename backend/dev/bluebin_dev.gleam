//// `gleam dev`: writes the JSON encoders and the TypeScript types of the
//// custom types in `bluebin/wire.gleam`. Run it after each change to that
//// file; `test/wire_test.gleam` fails while the written files are out of date.

import glance
import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile

pub const source_path = "src/bluebin/wire.gleam"

pub const gleam_path = "src/bluebin/wire_json.gleam"

pub const typescript_path = "../src/wire.ts"

pub fn main() -> Nil {
  let assert Ok(source) = simplifile.read(source_path)
  case generate(source) {
    Ok(Generated(gleam:, typescript:)) -> {
      let assert Ok(Nil) = simplifile.write(gleam_path, gleam)
      let assert Ok(Nil) = simplifile.write(typescript_path, typescript)
      io.println("Wrote " <> gleam_path <> " and " <> typescript_path)
    }
    Error(message) -> panic as { source_path <> ": " <> message }
  }
}

pub type Generated {
  Generated(gleam: String, typescript: String)
}

/// One custom type of `wire.gleam`.
type Definition {
  /// One variant with labelled fields: a JSON object.
  Record(name: String, doc: List(String), fields: List(Field))
  /// Variants with no fields only: a JSON string.
  Enum(name: String, doc: List(String), variants: List(Variant))
  /// Several variants, some with fields: a JSON object tagged by `kind`.
  Union(name: String, doc: List(String), variants: List(Variant))
}

type Variant {
  Variant(constructor: String, kind: String, fields: List(Field))
}

type Field {
  Field(label: String, kind: Kind, doc: List(String))
}

type Kind {
  Text
  Whole
  Decimal
  Flag
  Nullable(Kind)
  Many(Kind)
  Other(String)
}

pub fn generate(source: String) -> Result(Generated, String) {
  use module <- result.try(
    glance.module(source)
    |> result.replace_error("glance cannot parse it"),
  )
  // In the order of the source file: glance does not keep it.
  let custom_types =
    module.custom_types
    |> list.map(fn(definition) { definition.definition })
    |> list.sort(fn(a, b) { int.compare(a.location.start, b.location.start) })
  let names = list.map(custom_types, fn(custom) { custom.name })
  use definitions <- result.map(
    list.try_map(custom_types, definition(_, names, source)),
  )
  Generated(
    gleam: gleam_module(definitions),
    typescript: typescript_module(definitions),
  )
}

fn definition(
  custom: glance.CustomType,
  names: List(String),
  source: String,
) -> Result(Definition, String) {
  let glance.CustomType(name:, variants:, ..) = custom
  let doc = doc_before(source, custom.location.start)
  case custom.publicity, custom.parameters, variants {
    glance.Public, [], [glance.Variant(fields: [_, ..] as fields, ..)] -> {
      use fields <- result.map(
        list.try_map(fields, field(_, name, names, source)),
      )
      Record(name:, doc:, fields:)
    }
    glance.Public, [], [_, _, ..] -> {
      use variants <- result.try(
        list.try_map(variants, fn(variant) {
          use fields <- result.map(
            list.try_map(variant.fields, field(_, variant.name, names, source)),
          )
          Variant(
            constructor: variant.name,
            kind: variant_kind(variant.name, name),
            fields:,
          )
        }),
      )
      let kinds = list.map(variants, fn(variant) { variant.kind })
      case
        list.length(list.unique(kinds)) == list.length(kinds),
        list.all(variants, fn(variant) { variant.fields == [] })
      {
        False, _ -> Error(name <> " has two variants with the same kind")
        True, True -> Ok(Enum(name:, doc:, variants:))
        True, False -> Ok(Union(name:, doc:, variants:))
      }
    }
    _, _, _ ->
      Error(
        name
        <> " must be public, with no type parameter, and one variant with fields or several variants",
      )
  }
}

/// `Owner` → `owner`. The last word of the type name is dropped from the end
/// of the variant name, so that two types of the module can share a kind:
/// `ReworkItem` of `PriorityItem` → `rework`.
fn variant_kind(variant: String, type_: String) -> String {
  let word = last_word(type_)
  case variant != word && string.ends_with(variant, word) {
    True -> string.drop_end(variant, string.length(word))
    False -> variant
  }
  |> snake_case
}

/// `PriorityItem` → `Item`
fn last_word(name: String) -> String {
  let #(lower, rest) =
    string.to_graphemes(name)
    |> list.reverse
    |> list.split_while(fn(letter) { string.lowercase(letter) == letter })
  case rest {
    [capital, ..] -> capital <> string.concat(list.reverse(lower))
    [] -> name
  }
}

fn field(
  field: glance.VariantField,
  owner: String,
  names: List(String),
  source: String,
) -> Result(Field, String) {
  case field {
    glance.LabelledVariantField(item:, label:) -> {
      use kind <- result.map(
        kind(item, names)
        |> result.map_error(fn(type_) {
          owner <> "." <> label <> " has the unsupported type " <> type_
        }),
      )
      Field(label:, kind:, doc: doc_before(source, item.location.start))
    }
    glance.UnlabelledVariantField(..) ->
      Error(owner <> " has a field with no label")
  }
}

fn kind(type_: glance.Type, names: List(String)) -> Result(Kind, String) {
  case type_ {
    glance.NamedType(name: "String", module: None, parameters: [], ..) ->
      Ok(Text)
    glance.NamedType(name: "Int", module: None, parameters: [], ..) -> Ok(Whole)
    glance.NamedType(name: "Float", module: None, parameters: [], ..) ->
      Ok(Decimal)
    glance.NamedType(name: "Bool", module: None, parameters: [], ..) -> Ok(Flag)
    glance.NamedType(name: "Option", module: None, parameters: [inner], ..)
    | glance.NamedType(
        name: "Option",
        module: Some("option"),
        parameters: [inner],
        ..,
      ) -> kind(inner, names) |> result.map(Nullable)
    glance.NamedType(name: "List", module: None, parameters: [inner], ..) ->
      kind(inner, names) |> result.map(Many)
    glance.NamedType(name:, module: None, parameters: [], ..) ->
      case list.contains(names, name) {
        True -> Ok(Other(name))
        False -> Error(name)
      }
    glance.NamedType(name:, ..) -> Error(name)
    _ -> Error("other than a named type")
  }
}

/// The `///` lines right above the code that starts at byte `start`.
fn doc_before(source: String, start: Int) -> List(String) {
  let before =
    bit_array.from_string(source)
    |> bit_array.slice(0, start)
    |> result.try(bit_array.to_string)
    |> result.unwrap("")
  before
  |> string.split("\n")
  |> list.reverse
  |> list.drop(1)
  |> list.map(string.trim_start)
  |> list.take_while(fn(line) {
    string.starts_with(line, "///") && !string.starts_with(line, "////")
  })
  |> list.reverse
  |> list.map(fn(line) { string.trim(string.drop_start(line, 3)) })
}

// Gleam -----------------------------------------------------------------------

const max_width = 80

fn gleam_module(definitions: List(Definition)) -> String {
  "//// Generated by `gleam dev` from `bluebin/wire.gleam`. Do not edit.

import bluebin/wire
import gleam/json
" <> string.concat(list.map(definitions, encoder))
}

fn encoder(definition: Definition) -> String {
  let body = case definition {
    Record(fields:, ..) -> "  " <> object(fields, [], "value", "  ") <> "\n"
    Enum(variants:, ..) ->
      "  json.string(case value {\n"
      <> string.concat(
        list.map(variants, fn(variant) {
          "    wire."
          <> variant.constructor
          <> " -> \""
          <> variant.kind
          <> "\"\n"
        }),
      )
      <> "  })\n"
    Union(variants:, ..) ->
      "  case value {\n"
      <> string.concat(list.map(variants, union_arm))
      <> "  }\n"
  }
  "\npub fn "
  <> snake_case(definition.name)
  <> "(value: wire."
  <> definition.name
  <> ") -> json.Json {\n"
  <> body
  <> "}\n"
}

fn union_arm(variant: Variant) -> String {
  let tag = #("kind", "json.string(\"" <> variant.kind <> "\")")
  case variant.fields {
    [] -> {
      let line =
        "    wire."
        <> variant.constructor
        <> " -> "
        <> object([], [tag], "", "    ")
      case string.length(line) <= max_width {
        True -> line <> "\n"
        False ->
          "    wire."
          <> variant.constructor
          <> " ->\n      "
          <> object([], [tag], "", "      ")
          <> "\n"
      }
    }
    fields ->
      "    wire."
      <> variant.constructor
      <> "(..) as variant ->\n      "
      <> object(fields, [tag], "variant", "      ")
      <> "\n"
  }
}

/// `json.object([...])`, its first line at `indent`, the entries one level in.
/// `first` are entries written before the fields, as `#(key, value)` code.
fn object(
  fields: List(Field),
  first: List(#(String, String)),
  value: String,
  indent: String,
) -> String {
  let entries =
    list.append(
      first,
      list.map(fields, fn(field) {
        #(
          camel_case(field.label),
          expression(field.kind, value <> "." <> field.label),
        )
      }),
    )
  case fields {
    [] ->
      "json.object(["
      <> string.join(
        list.map(entries, fn(entry) {
          "#(\"" <> entry.0 <> "\", " <> entry.1 <> ")"
        }),
        ", ",
      )
      <> "])"
    _ -> {
      let inner = indent <> "  "
      "json.object([\n"
      <> string.concat(
        list.map(entries, fn(entry) {
          let key = "\"" <> entry.0 <> "\""
          let line = inner <> "#(" <> key <> ", " <> entry.1 <> "),"
          case string.length(line) <= max_width {
            True -> line <> "\n"
            False ->
              inner
              <> "#(\n"
              <> inner
              <> "  "
              <> key
              <> ",\n"
              <> inner
              <> "  "
              <> entry.1
              <> ",\n"
              <> inner
              <> "),\n"
          }
        }),
      )
      <> indent
      <> "])"
    }
  }
}

fn expression(kind: Kind, value: String) -> String {
  case kind {
    Nullable(inner) ->
      "json.nullable(" <> value <> ", " <> function(inner) <> ")"
    Many(inner) -> "json.array(" <> value <> ", " <> function(inner) <> ")"
    _ -> function(kind) <> "(" <> value <> ")"
  }
}

fn function(kind: Kind) -> String {
  case kind {
    Text -> "json.string"
    Whole -> "json.int"
    Decimal -> "json.float"
    Flag -> "json.bool"
    Other(name) -> snake_case(name)
    Nullable(_) | Many(_) -> "fn(item) { " <> expression(kind, "item") <> " }"
  }
}

// TypeScript ------------------------------------------------------------------

const ts_max_width = 100

fn typescript_module(definitions: List(Definition)) -> String {
  "// Generated by `gleam dev` in backend/ from backend/src/bluebin/wire.gleam. Do not edit.\n"
  <> string.concat(list.map(definitions, typescript_type))
}

fn typescript_type(definition: Definition) -> String {
  let head = "export type " <> definition.name
  "\n"
  <> jsdoc(definition.doc, "")
  <> case definition {
    Record(fields:, ..) -> head <> " = " <> ts_object(fields, [], "") <> "\n"
    Enum(variants:, ..) -> {
      let kinds =
        list.map(variants, fn(variant) { "\"" <> variant.kind <> "\"" })
      let line = head <> " = " <> string.join(kinds, " | ")
      case string.length(line) <= ts_max_width {
        True -> line <> "\n"
        False ->
          head
          <> " =\n"
          <> string.concat(list.map(kinds, fn(kind) { "  | " <> kind <> "\n" }))
      }
    }
    Union(variants:, ..) ->
      head
      <> " =\n"
      <> string.concat(
        list.map(variants, fn(variant) {
          "  | "
          <> ts_object(
            variant.fields,
            ["kind: \"" <> variant.kind <> "\""],
            "    ",
          )
          <> "\n"
        }),
      )
  }
}

/// An object type, its last line at `indent`. `first` are members written
/// before the fields.
fn ts_object(
  fields: List(Field),
  first: List(String),
  indent: String,
) -> String {
  let inner = indent <> "  "
  "{\n"
  <> string.concat(list.map(first, fn(member) { inner <> member <> "\n" }))
  <> string.concat(
    list.map(fields, fn(field) {
      jsdoc(field.doc, inner)
      <> inner
      <> camel_case(field.label)
      <> ": "
      <> ts(field.kind)
      <> "\n"
    }),
  )
  <> indent
  <> "}"
}

fn jsdoc(lines: List(String), indent: String) -> String {
  case lines {
    [] -> ""
    [line] -> indent <> "/** " <> line <> " */\n"
    lines ->
      indent
      <> "/**\n"
      <> string.concat(
        list.map(lines, fn(line) {
          case line {
            "" -> indent <> " *\n"
            _ -> indent <> " * " <> line <> "\n"
          }
        }),
      )
      <> indent
      <> " */\n"
  }
}

fn ts(kind: Kind) -> String {
  case kind {
    Text -> "string"
    Whole | Decimal -> "number"
    Flag -> "boolean"
    Other(name) -> name
    Nullable(inner) -> ts(inner) <> " | null"
    Many(Nullable(_) as inner) -> "(" <> ts(inner) <> ")[]"
    Many(inner) -> ts(inner) <> "[]"
  }
}

// Names -----------------------------------------------------------------------

/// `forecast_late_days` → `forecastLateDays`
fn camel_case(label: String) -> String {
  case string.split(label, "_") {
    [first, ..rest] -> first <> string.concat(list.map(rest, string.capitalise))
    [] -> label
  }
}

/// `BlueBin` → `blue_bin`
fn snake_case(name: String) -> String {
  name
  |> string.to_graphemes
  |> list.index_map(fn(letter, index) {
    let lower = string.lowercase(letter)
    case index > 0 && lower != letter {
      True -> "_" <> lower
      False -> lower
    }
  })
  |> string.concat
}
