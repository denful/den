# A schema entry that closes its kind: `den.schema.<kind> = den.lib.strict;`.
#
# Strictness is a property of the kind, so it is a collection on the entry, not a module.
# The kind's instance type is then built closed (gen-schema's strict freeform) rather than
# open; a second freeform type stacked on the open one is not a type the module system
# can merge.
_: { isStrict = true; }
