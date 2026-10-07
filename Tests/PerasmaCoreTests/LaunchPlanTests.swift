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

    func testLegacyEnvironmentStillDecodes() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"name\":\"Existing\"}".utf8)
        let environment = try JSONDecoder().decode(WindowsEnvironment.self, from: data)
        XCTAssertNil(environment.graphics)
    }
    func testGraphicsOverridesExcludeDXGIAndD3D9() {
        XCTAssertEqual(ComponentPolicy.overrides(graphics: .dxvk), "d3d10core,d3d11=n,b")
        XCTAssertNil(ComponentPolicy.overrides(graphics: nil))
        XCTAssertEqual(ComponentPolicy.graphicsDLLs, ["d3d10core.dll", "d3d11.dll"])
    }
    func testRejectsArchiveTraversalAndWrongRoots() {
        XCTAssertTrue(ComponentPolicy.safeArchiveEntry("dxvk-v1.10.3/x64/d3d11.dll", root: "dxvk-v1.10.3"))
        for entry in ["/dxvk-v1.10.3/a", "dxvk-v1.10.3/../a", "other/d3d11.dll", "dxvk-v1.10.3"] {
            XCTAssertFalse(ComponentPolicy.safeArchiveEntry(entry, root: "dxvk-v1.10.3"))
        }
    }
}
