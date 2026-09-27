import Testing
@testable import Resolume

@Test("instalações reais expõem capability apenas no macOS")
func discoveredInstallationsAreMacOnly() {
    for installation in ResolumeLocator.discover() {
        #expect(installation.product.capability.isAvailable(on: .macOS))
        #expect(!installation.product.capability.isAvailable(on: .iOS))
    }
}

@Test("caminho do MCP segue o layout do fabricante")
func mcpPathMatchesVendorLayout() {
    #expect(
        ResolumeProduct.arena.mcpExecutablePath
            == "/Applications/Resolume Arena/mcp/resolume_arena_mcp_server")
}
