---

name: Bug report with tests
about: "Issues are for maintainer's time-allocated tasks! Use Discussions for questions, feature-requests, problem solving, etc."
title: 'BUG: '
labels: 'bug'
assignees: ''

---

> [!NOTE]
> The BUG tag is for failing code with tests.
> DO-NOT use it unless you have code for a failing test.
> You are welcome to send either bogus repo or just a `denTest` code snippet reproducing a bug.
> Issues are for maintainer's time-allocated tasks! Use Discussions for questions, feature-requests, problem solving, etc.

Please read https://den.oeiuwq.com/tutorials/bogus/ first.

If you have found a bug, please share a reproduction repository with us.

First step is to clone the `bogus` template and edit `modules/bug.nix`.

```console
nix flake init -t github:denful/den#bogus
nix flake update den
vim modules/bug.nix
nix flake check
```

Your repository will help us verify that we can reproduce the bug in a minimal environment - Your repo has CI actions enabled. When the bug has been fixed we can use your same code as a non-regression test to ensure bugs do not appear again.

If you found a bug regression please edit the CI workflow to include main and any other revision to test and show something was working before main.

### Description

Provide a very small description of the intended and the actual behaviour.

Share a link to a [discussion](https://github.com/denful/den/discussions) to keep track of it.
