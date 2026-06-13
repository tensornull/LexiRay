// Scenario: the Settings section shows the App Identity panel reporting a
// stable workspace-build identity, with the diagnostic controls reachable.
openMainWindow()

require(pressLexiRayElement(identifier: "SidebarSettings"), "settings sidebar item was not reachable")
require(
  waitFor("app identity panel", timeout: 5, { lexirayVisibleTextContains("App Identity") }),
  "app identity panel was not reachable"
)
require(
  waitFor("local development signing authority", timeout: 5, {
    lexirayVisibleTextContains("LexiRay Local Development")
  }),
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
pass()
