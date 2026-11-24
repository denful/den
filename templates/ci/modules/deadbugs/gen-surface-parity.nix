# den's public gen surface stays what the pinned gen gives, whichever gen the
# registry runs on: `den.lib.schema` and each `den.lib.schema.gen` member export
# exactly these names. gen's paired constructions (gen-schema mkInstancePaired,
# gen-merge refusingSubmodulePaired) are filtered out; den reaches them only
# through its one adapter (nix/lib/schema.nix __mkInstancePaired). `__` names
# are den's private convention, not public surface, so they're left out.
{ denTest, lib, ... }:
let
  public = s: builtins.filter (n: !(lib.hasPrefix "__" n)) (builtins.attrNames s);
in
{
  flake.tests.gen-surface-parity = {
    test-schema-names = denTest (
      { den, ... }:
      {
        expr = public den.lib.schema;
        expected = [
          "_internal"
          "ancestorsForKind"
          "applyMixin"
          "beta"
          "blame"
          "checkRefinements"
          "composeMixins"
          "constructionRelation"
          "declarationOf"
          "defaultOnError"
          "emitModule"
          "entryReservation"
          "evalSchema"
          "fieldDeclarationMarker"
          "fieldDeclarationsIn"
          "fieldRef"
          "fieldRefMarker"
          "fieldRefsIn"
          "filterValidators"
          "formatErrors"
          "gen"
          "identityHashForKind"
          "identityKeysForKind"
          "isFieldDeclaration"
          "isFieldRef"
          "keySemanticsRecords"
          "kindEq"
          "mkCodec"
          "mkFieldDeclaration"
          "mkFieldValidator"
          "mkIdentityModule"
          "mkInstanceRegistry"
          "mkInstanceType"
          "mkMixin"
          "mkSchemaEntryType"
          "mkSchemaOption"
          "mkStrictModule"
          "mkValidator"
          "ref"
          "refined"
          "refinements"
          "renderDocs"
          "runValidators"
          "schemaFn"
          "setOf"
          "strictCompatModules"
          "toSet"
          "validateInstances"
        ];
      }
    );

    test-gen-algebra-names = denTest (
      { den, ... }:
      {
        expr = public den.lib.schema.gen.algebra;
        expected = [
          "comparisonSubject"
          "componentsPreimage"
          "conservativeEq"
          "declaresSubject"
          "either"
          "hasDeclaredSubject"
          "hasMark"
          "identityOf"
          "isExact"
          "markOf"
          "mkIntensional"
          "preimageTagOf"
          "record"
          "regimeTagOf"
          "sealedCollisionEq"
          "sealedMarker"
          "subjectEntry"
          "term"
        ];
      }
    );

    test-gen-identity-names = denTest (
      { den, ... }:
      {
        expr = public den.lib.schema.gen.identity;
        expected = [
          "hashIdentity"
        ];
      }
    );

    test-gen-merge-names = denTest (
      { den, ... }:
      {
        expr = public den.lib.schema.gen.merge;
        expected = [
          "anything"
          "attrsOf"
          "bandedLeaves"
          "closuresFirst"
          "declaredOptions"
          "deferredModule"
          "deriveType"
          "either"
          "engineOptionNames"
          "evalModuleTree"
          "importedCarried"
          "importedTypeWalkFuel"
          "lazyAttrsOf"
          "lint"
          "listOf"
          "mergeDefaultOption"
          "mergeDefs"
          "mergeDefsPartial"
          "mergeOneOption"
          "mergeTypes"
          "mkAfter"
          "mkBefore"
          "mkCoreValue"
          "mkDefault"
          "mkDefinition"
          "mkForce"
          "mkIf"
          "mkMerge"
          "mkOption"
          "mkOptionDefault"
          "mkOptionType"
          "mkOrder"
          "mkOverride"
          "moduleSyntax"
          "nullOr"
          "oneOf"
          "option"
          "partialAttrsOf"
          "partialSubmodule"
          "priorityBand"
          "pureModule"
          "raw"
          "refusingSubmodule"
          "showOption"
          "submodule"
          "types"
          "verifyValue"
        ];
      }
    );

    test-gen-members = denTest (
      { den, ... }:
      {
        expr = builtins.attrNames den.lib.schema.gen;
        expected = [
          "algebra"
          "identity"
          "merge"
        ];
      }
    );
  };
}
