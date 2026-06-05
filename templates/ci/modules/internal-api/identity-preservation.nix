# Tests for identity preservation through the resolve pipeline.
# Legacy resolve.withAdapter tests removed — the API no longer exists.
# TODO: rewrite using fx pipeline introspection if needed.
{ denTest, lib, ... }:
{
  flake.tests.identity-preservation = { };
}
