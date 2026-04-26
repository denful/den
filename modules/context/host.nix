{ ... }:
{
  # Root self-provide must stay as a provides entry (not include) because
  # the pipeline resolves self-provides before transitions, enabling deferred
  # include drain during context widening. Moving to includes breaks this ordering.
  den.stages.host.provides.host = { host }: host.aspect;
}
