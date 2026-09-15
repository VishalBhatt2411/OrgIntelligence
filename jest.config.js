const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  /*
   * `.claude/worktrees/*` holds git worktrees created by tooling, each a full copy of
   * `force-app`. Without this, Jest collects those copies' test files and runs them against
   * THIS tree's `c/*` modules (module resolution is rooted here), so a stale worktree test
   * fails against current components — and every suite is otherwise counted twice, which
   * silently inflates suite/test totals.
   */
  modulePathIgnorePatterns: [
    "<rootDir>/.localdevserver",
    "<rootDir>/.claude/worktrees"
  ],
  moduleNameMapper: {
    ...(jestConfig.moduleNameMapper || {}),
    /*
     * CSS-only LWC modules (see ADR-0028): each has a .css file and a .js-meta.xml, but
     * deliberately no .js entry point. sfdx-lwc-jest's resolver only maps modules that expose
     * a JS module, so `@import 'c/oiDesignTokens'` inside a component stylesheet fails to
     * resolve under Jest even though it compiles and deploys correctly. Map each to its own
     * stylesheet — Jest's CSS transform turns it into an inert module, which is the right
     * behaviour: token values are a rendering concern jsdom does not evaluate, so no test
     * should ever assert on them.
     *
     * Add any new CSS-only module to this alternation.
     */
    "^c/(oiDesignTokens|oiComboboxStyles|oiButtonStyles)$":
      "<rootDir>/force-app/main/default/lwc/$1/$1.css"
  }
};
