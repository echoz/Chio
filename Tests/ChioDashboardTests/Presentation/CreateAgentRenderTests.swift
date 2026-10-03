@testable import ChioDashboard
import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct CreateAgentRenderTests {
    @Test("The form keeps actions and keyboard help visible across sizes and themes",
          arguments: [CellSize(width: 100, height: 30), CellSize(width: 50, height: 30),
                      CellSize(width: 36, height: 18)], [false, true])
    func layout(size: CellSize, light: Bool) {
        let view = CreateAgentView(draft: .constant(AgentDraft()), isLight: .constant(light),
                                   create: {}, cancel: {})
        let frame = DefaultRenderer().render(
            view, proposal: .init(width: size.width, height: size.height), frameInstant: .zero
        )
        let text = frame.rasterSurface.lines.joined(separator: "\n")
        #expect(frame.rasterSurface.size == size)
        #expect(text.contains("/ create agent"))
        #expect(text.contains("Name"))
        #expect(text.contains("Create agent"))
        #expect(text.contains("Cancel"))
        #expect(text.contains("esc cancel"))
        #expect(text.contains("^T theme"))
        #expect(!text.contains("Error:"))
        if size.height >= 30 {
            #expect(text.contains("Role"))
            #expect(text.contains("Start immediately"))
        }
        let theme: ChioTheme = light ? .light : .default
        #expect(frame.rasterSurface.cells.flatMap { $0 }.contains {
            $0.character == "N" && $0.style?.foregroundColor == theme.colors.heading
        })
    }
}
