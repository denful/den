{ denTest, inputs, ... }:
{

  flake.tests.deadbugs-namespace-deep-aspect = {

    test-tools-has-underscore = denTest (
      { den, provider, ... }:
      {
        imports = [
          (inputs.den.namespace "provider" [
            true
            inputs.provider
          ])
        ];
        expr = provider.tools ? _;
        expected = true;
      }
    );

    test-dev-has-underscore = denTest (
      { provider, ... }:
      {
        imports = [
          (inputs.den.namespace "provider" [
            true
            inputs.provider
          ])
        ];
        expr = provider.tools.provides.dev ? _;
        expected = true;
      }
    );

    test-external-flake = denTest (
      {
        provider,
        igloo,
        ...
      }:
      {
        imports = [
          (inputs.den.namespace "provider" [
            true
            inputs.provider
          ])
        ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ provider.tools.provides.dev.provides.editors ];
        expr = igloo.programs.vim.enable;
        expected = true;
      }
    );

    test-functor-atLeast-fires-with-host-context = denTest (
      {
        provider,
        igloo,
        ...
      }:
      {
        imports = [
          (inputs.den.namespace "provider" [
            true
            inputs.provider
          ])
        ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ provider.tools.provides.dev.provides.host-stamp ];
        expr = igloo.environment.sessionVariables.PROVIDER_HOST;
        expected = "igloo";
      }
    );

    test-functor-exactly-fires-only-in-user-context = denTest (
      {
        den,
        provider,
        igloo,
        ...
      }:
      {
        imports = [
          (inputs.den.namespace "provider" [
            true
            inputs.provider
          ])
        ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.provides.to-users.includes = [ provider.tools.provides.dev.provides.user-stamp ];
        den.schema.user.includes = [ den.provides.mutual-provider ];
        expr = igloo.users.users.tux.description;
        expected = "user-of-igloo";
      }
    );

  };

}
