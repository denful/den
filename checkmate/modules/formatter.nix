{
  perSystem.treefmt.settings.global.excludes = [
    ".claude/**"
    ".agents/**"
    ".github/*TEMPLATE*/*"
    ".github/CODEOWNERS"
    "docs/*"
    "Justfile"
    "AGENT*.md"
    "CLAUDE.md"
    "*.txt"
    "*.svg"
    "ci.bash"
    "templates/fleet-demo/diagrams/*"
    "templates/fleet-demo/README.md"
    "templates/diagram-demo/diagrams/*"
    "templates/diagram-demo/README.md"
  ];
  perSystem.treefmt.programs.deadnix.enable = false;
  perSystem.treefmt.programs.nixf-diagnose.enable = false;
}
