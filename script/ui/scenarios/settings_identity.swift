// Scenario: the Settings section shows the App Identity panel reporting a
// stable workspace-build identity, with the diagnostic controls reachable.
openMainWindow()

require(pressLexiRayElement(identifier: "SidebarSettings"), "settings sidebar item was not reachable")
require(
  waitFor("app identity panel", timeout: 5) { lexirayVisibleTextContains("App Identity") },
  "app identity panel was not reachable"
)
require(
  waitFor("local development signing authority", timeout: 5) {
    lexirayVisibleTextContains("LexiRay Local Development")
  },
  "workspace build did not report the local development signing identity"
)
require(
  !lexirayVisibleTextContains("Unstable"),
  "workspace build reported an unstable app identity"
)
require(
  !lexirayVisibleTextContains("Multiple Copies Running"),
  "app identity panel reported duplicate running copies"
)
require(
  axElement(identifier: "AppIdentityOpenInstallLocationButton") != nil
    && axElement(identifier: "AppIdentityOpenPrivacySettingsButton") != nil
    && axElement(identifier: "AppIdentityCopyDiagnosticsButton") != nil,
  "app identity action buttons were not reachable"
)
require(
  scrollMainWindowToReveal(identifier: "AppIdentityCopyDiagnosticsButton"),
  "app identity panel could not be scrolled into view"
)

snapMain("settings-app-identity")

restartWorkspaceApp(extraArguments: [
  "--lexiray-acceptance-login-item-status", "notFound"
])
openMainWindow()
require(pressLexiRayElement(identifier: "SidebarSettings"), "settings sidebar item was not reachable after restart")
require(
  waitFor("actionable notFound Login Item state", timeout: 5) {
    lexirayVisibleTextContains("macOS has no Login Item record for LexiRay")
  },
  "notFound Login Item state was not explained"
)
guard let startAtLoginToggle = axElement(identifier: "StartAtLoginToggle") else {
  fail("Start at login toggle was not reachable")
}

require(axBool(startAtLoginToggle, kAXEnabledAttribute) == true, "notFound disabled the Start at login toggle")
snapMain("settings-login-item-not-found-before-register")
require(pressLexiRayElement(identifier: "StartAtLoginToggle"), "Start at login toggle could not be enabled")
require(
  waitFor("isolated Login Item registration", timeout: 5) { lexirayVisibleTextContains("Enabled") },
  "notFound did not transition through register() to enabled"
)
snapMain("settings-login-item-not-found")
pass()
