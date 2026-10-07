import XCTest
@testable import PerasmaCore
final class LaunchPlanTests: XCTestCase {
    func testAcceptsEXECaseInsensitive() { XCTAssertTrue(LaunchPlan.accepts(URL(fileURLWithPath: "/tmp/APP.EXE"))) }
    func testAcceptsMSI() { XCTAssertTrue(LaunchPlan.accepts(URL(fileURLWithPath: "/tmp/setup.msi"))) }
    func testRejectsOtherTypes() { XCTAssertFalse(LaunchPlan.accepts(URL(fileURLWithPath: "/tmp/readme.txt"))) }
    func testEXEArgumentsPreserveSpacesAndShellSyntax() { let path = "/tmp/A $HOME; file.exe"; XCTAssertEqual(LaunchPlan.arguments(for: URL(fileURLWithPath: path)), [path]) }
    func testMSIArguments() { XCTAssertEqual(LaunchPlan.arguments(for: URL(fileURLWithPath: "/tmp/setup.msi")), ["msiexec", "/i", "/tmp/setup.msi"]) }
    func testPrefixesUseUUIDNotNames() { let id = UUID(); XCTAssertEqual(LaunchPlan.prefix(root: URL(fileURLWithPath: "/tmp/root"), id: id).lastPathComponent, id.uuidString) }
    func testDefaultsRequireLaunchReview() { XCTAssertTrue(Preferences().confirmLaunch); XCTAssertFalse(Preferences().onboardingComplete); XCTAssertEqual(Preferences().runtimePath, "") }
    func testRoundTripLibrary() throws { var library = Library(); let env = WindowsEnvironment(name: "Synthetic"); library.environments.append(env); library.apps.append(WindowsApp(name: "Demo", path: "/tmp/demo.exe", category: .programs, environmentID: env.id)); let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library)); XCTAssertEqual(decoded.apps, library.apps) }
}
