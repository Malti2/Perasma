import XCTest
@testable import PerasmaCore
final class LaunchPlanTests: XCTestCase {
    func testAcceptsEXECaseInsensitive() { XCTAssertTrue(LaunchPlan.accepts(URL(fileURLWithPath: "/tmp/APP.EXE"))) }
    func testAcceptsMSI() { XCTAssertTrue(LaunchPlan.accepts(URL(fileURLWithPath: "/tmp/setup.msi"))) }
    func testRejectsOtherTypes() { XCTAssertFalse(LaunchPlan.accepts(URL(fileURLWithPath: "/tmp/readme.txt"))) }
    func testEXEArgumentsPreserveSpacesAndShellSyntax() { let path = "/tmp/A $HOME; file.exe"; XCTAssertEqual(LaunchPlan.arguments(for: URL(fileURLWithPath: path)), [path]) }
    func testMSIArguments() { XCTAssertEqual(LaunchPlan.arguments(for: URL(fileURLWithPath: "/tmp/setup.msi")), ["msiexec", "/i", "/tmp/setup.msi"]) }
    func testPrefixesUseUUIDNotNames() { let id = UUID(); XCTAssertEqual(LaunchPlan.prefix(root: URL(fileURLWithPath: "/tmp/root"), id: id).lastPathComponent, id.uuidString) }
    func testDefaultsRequireLaunchReview() { XCTAssertTrue(Preferences().confirmLaunch); XCTAssertFalse(Preferences().onboardingComplete); XCTAssertEqual(Preferences().runtimePath, ""); XCTAssertEqual(Preferences().sort, .name) }
    func testRoundTripLibrary() throws { var library = Library(); let env = WindowsEnvironment(name: "Synthetic"); library.environments.append(env); library.apps.append(WindowsApp(name: "Demo", path: "/tmp/demo.exe", category: .programs, environmentID: env.id)); let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library)); XCTAssertEqual(decoded.apps, library.apps) }

    func testLegacyEnvironmentStillDecodes() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"name\":\"Existing\"}".utf8)
        let environment = try JSONDecoder().decode(WindowsEnvironment.self, from: data)
        XCTAssertNil(environment.graphics)
    }
    func testLegacyAppStillDecodesWithNewDefaults() throws {
        let id = UUID(); let env = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"name\":\"Old\",\"path\":\"/tmp/old.exe\",\"category\":\"Games\",\"environmentID\":\"\(env.uuidString)\"}".utf8)
        let app = try JSONDecoder().decode(WindowsApp.self, from: data)
        XCTAssertFalse(app.favorite)
        XCTAssertEqual(app.launchArguments, "")
        XCTAssertNil(app.lastOpened)
        XCTAssertNil(app.iconPath)
    }
    func testNewAppFieldsRoundTrip() throws {
        let app = WindowsApp(name: "New", path: "/tmp/new.exe", category: .games, environmentID: UUID(), lastOpened: Date(timeIntervalSince1970: 1_700_000_000), favorite: true, launchArguments: "-windowed")
        let decoded = try JSONDecoder().decode(WindowsApp.self, from: JSONEncoder().encode(app))
        XCTAssertEqual(decoded, app)
    }
    func testLegacyPreferencesStillDecode() throws {
        let data = Data("{\"runtimePath\":\"/opt/wine\",\"layout\":\"List\",\"confirmLaunch\":false,\"showInspector\":false,\"onboardingComplete\":true}".utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(preferences.runtimePath, "/opt/wine")
        XCTAssertEqual(preferences.layout, .list)
        XCTAssertFalse(preferences.confirmLaunch)
        XCTAssertTrue(preferences.onboardingComplete)
        XCTAssertEqual(preferences.sort, .name)
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
    func testEnvironmentVariables() {
        let prefix = URL(fileURLWithPath: "/tmp/prefix")
        XCTAssertEqual(LaunchPlan.environmentVariables(prefix: prefix, graphics: nil), ["WINEPREFIX": "/tmp/prefix"])
        XCTAssertEqual(LaunchPlan.environmentVariables(prefix: prefix, graphics: .dxvk), ["WINEPREFIX": "/tmp/prefix", "WINEDLLOVERRIDES": "d3d10core,d3d11=n,b"])
    }
}

final class LaunchArgumentsTests: XCTestCase {
    func testEmpty() { XCTAssertEqual(LaunchArguments.parse(""), []); XCTAssertEqual(LaunchArguments.parse("   "), []) }
    func testPlainFlags() { XCTAssertEqual(LaunchArguments.parse("-windowed -dx11"), ["-windowed", "-dx11"]) }
    func testDoubleQuotedValueWithSpaces() { XCTAssertEqual(LaunchArguments.parse("-name \"My Game\" -x"), ["-name", "My Game", "-x"]) }
    func testSingleQuotedValueWithSpaces() { XCTAssertEqual(LaunchArguments.parse("--profile 'a b'"), ["--profile", "a b"]) }
    func testEmptyQuotedArgumentIsKept() { XCTAssertEqual(LaunchArguments.parse("-a \"\""), ["-a", ""]) }
    func testEscapedQuoteInsideDoubleQuotes() { XCTAssertEqual(LaunchArguments.parse("\"say \\\"hi\\\"\""), ["say \"hi\""]) }
    func testUnterminatedQuoteTakesTheRest() { XCTAssertEqual(LaunchArguments.parse("-a \"rest of it"), ["-a", "rest of it"]) }
    func testCustomArgumentsAppendToEXE() { XCTAssertEqual(LaunchPlan.arguments(for: URL(fileURLWithPath: "/tmp/g.exe"), customArguments: "-windowed"), ["/tmp/g.exe", "-windowed"]) }
    func testCustomArgumentsAppendAfterMSIPath() { XCTAssertEqual(LaunchPlan.arguments(for: URL(fileURLWithPath: "/tmp/s.msi"), customArguments: "/quiet"), ["msiexec", "/i", "/tmp/s.msi", "/quiet"]) }
}

final class LibraryFilterTests: XCTestCase {
    private func makeLibrary() -> (Library, WindowsEnvironment) {
        var library = Library()
        let env = WindowsEnvironment(name: "Main")
        library.environments.append(env)
        library.apps = [
            WindowsApp(name: "Zulu Editor", path: "/apps/zulu.exe", category: .programs, environmentID: env.id),
            WindowsApp(name: "Alpha Game", path: "/games/alpha.exe", category: .games, environmentID: env.id, lastOpened: Date(timeIntervalSince1970: 100), favorite: true),
            WindowsApp(name: "Beta Game", path: "/games/beta.exe", category: .games, environmentID: env.id, lastOpened: Date(timeIntervalSince1970: 200)),
        ]
        return (library, env)
    }
    func testSectionFiltering() {
        let (library, _) = makeLibrary()
        XCTAssertEqual(library.filteredApps(section: .all).count, 3)
        XCTAssertEqual(library.filteredApps(section: .games).map(\.name), ["Alpha Game", "Beta Game"])
        XCTAssertEqual(library.filteredApps(section: .programs).map(\.name), ["Zulu Editor"])
        XCTAssertEqual(library.filteredApps(section: .favorites).map(\.name), ["Alpha Game"])
    }
    func testRecentSectionOnlyOpenedAndNewestFirst() {
        let (library, _) = makeLibrary()
        XCTAssertEqual(library.filteredApps(section: .recent).map(\.name), ["Beta Game", "Alpha Game"])
    }
    func testRecentlyOpenedSortPutsNeverOpenedLast() {
        let (library, _) = makeLibrary()
        XCTAssertEqual(library.filteredApps(section: .all, sort: .recentlyOpened).map(\.name), ["Beta Game", "Alpha Game", "Zulu Editor"])
    }
    func testNameSort() {
        let (library, _) = makeLibrary()
        XCTAssertEqual(library.filteredApps(section: .all, sort: .name).map(\.name), ["Alpha Game", "Beta Game", "Zulu Editor"])
    }
    func testCategorySortGroupsAndSortsWithin() {
        let (library, _) = makeLibrary()
        XCTAssertEqual(library.filteredApps(section: .all, sort: .category).map(\.name), ["Alpha Game", "Beta Game", "Zulu Editor"])
    }
    func testSearchMatchesNameFileNameAndCategory() {
        let (library, _) = makeLibrary()
        XCTAssertEqual(library.filteredApps(section: .all, search: "zulu").map(\.name), ["Zulu Editor"])
        XCTAssertEqual(library.filteredApps(section: .all, search: "BETA.EXE").map(\.name), ["Beta Game"])
        XCTAssertEqual(library.filteredApps(section: .all, search: "games").count, 2)
        XCTAssertEqual(library.filteredApps(section: .all, search: "nope"), [])
    }
    func testContainsAppNormalizesPaths() {
        let (library, _) = makeLibrary()
        XCTAssertTrue(library.containsApp(atPath: "/games/../games/alpha.exe"))
        XCTAssertFalse(library.containsApp(atPath: "/games/other.exe"))
    }
    func testEnvironmentLookups() {
        let (library, env) = makeLibrary()
        XCTAssertEqual(library.environment(for: library.apps[0])?.id, env.id)
        XCTAssertEqual(library.apps(in: env.id).count, 3)
        XCTAssertEqual(library.apps(in: UUID()).count, 0)
    }
}
