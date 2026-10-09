@testable import Chio
import SwiftTUIRuntime
import Testing

@MainActor
struct MapOverlayRenderingTests {
    @Test("Water boundaries remain legible over both filled and unfilled cells")
    func waterBoundaryContrast() throws {
        let viewport = try MapViewport(columns: 10, rows: 10)
        let points = rectangle(2, 2, 8, 8)
        let geometry = map(lines: [.init(featureID: "lake", kind: .water, points: points)],
                           polygons: [.init(featureID: "lake", kind: .water, rings: [points])])
        for theme in [ChioTheme.default, .light, .btop] {
            for fills in [false, true] {
                let drawing = try MapDrawing(map: geometry, viewport: viewport, colors: theme.colors,
                                              waterColor: theme.map.water, parkColor: theme.map.park, fills: fills)
                let cell = render(drawing).cells[2][2]
                #expect(cell.character != " ")
                #expect(cell.style?.foregroundColor == theme.colors.secondaryText)
                #expect(cell.style?.foregroundColor != cell.style?.backgroundColor)
                #expect(cell.style?.backgroundColor == (fills ? theme.map.water : theme.colors.surface))
            }
        }
    }

    @Test("The selected coincident marker wins and keeps its label when other labels are hidden")
    func selectedMarkerPriority() throws {
        let camera = try makeCamera()
        let viewport = try MapViewport(columns: 40, rows: 20)
        let coordinate = camera.center
        let ordinary = try MapMarker(id: "ordinary", coordinate: coordinate, title: "Ordinary")
        let selected = try MapMarker(id: "selected", coordinate: coordinate, title: "Selected")
        let placement = MapMarkerPlacement(markers: [ordinary, selected], selection: selected.id,
                                            camera: camera, viewport: viewport, showsLabels: false)
        #expect(placement.markers.map(\.value.id) == [selected.id])
        #expect(placement.markers[0].isSelected)
        #expect(placement.labels.map(\.id) == [selected.id])
        #expect(placement.labels[0].text == "Selected")
        let unselected = MapMarkerPlacement(markers: [ordinary, selected], selection: "unknown",
                                             camera: camera, viewport: viewport, showsLabels: false)
        #expect(unselected.markers.map(\.value.id) == [ordinary.id])
        #expect(!unselected.markers[0].isSelected)
        #expect(unselected.labels.isEmpty)
    }

    @Test("Marker names measure wide Unicode, choose a fitting side and bound clipped label width")
    func markerLabelBounds() throws {
        let camera = try makeCamera()
        let viewport = try MapViewport(columns: 20, rows: 20)
        let marker = try MapMarker(id: "wide", coordinate: MapCoordinate(latitude: 0, longitude: 8.5), title: "東京")
        let placement = MapMarkerPlacement(markers: [marker], selection: marker.id,
                                            camera: camera, viewport: viewport, showsLabels: true)
        let label = try #require(placement.labels.first)
        #expect(label.width == 4)
        #expect(label.column == 12) // Leave space for the selected ring on the right.
        #expect(label.column + label.width <= viewport.columns)

        let long = try MapMarker(id: "long", coordinate: camera.center, title: String(repeating: "界", count: 20))
        let roomy = try MapViewport(columns: 80, rows: 20)
        let clipped = MapMarkerPlacement(markers: [long], selection: long.id,
                                          camera: camera, viewport: roomy, showsLabels: true)
        #expect(clipped.labels.first?.width == 32)
        #expect(clipped.labels.first?.text == long.title)
        let labelView = Text(verbatim: long.title).lineLimit(1)
            .frame(width: 32, height: 1, alignment: .leading).clipped()
        let surface = DefaultRenderer().render(labelView, proposal: .init(width: 32, height: 1)).rasterSurface
        #expect(surface.size == CellSize(width: 32, height: 1))
        #expect(surface.cells[0].filter { $0.character == "界" && $0.spanWidth == 2 }.count == 15)
        #expect(surface.lines[0].contains("…")) // Native one-line truncation keeps whole clusters.
        #expect(!surface.cells[0].contains { $0.character == "�" })
        let narrow = MapMarkerPlacement(markers: [long], selection: long.id,
                                         camera: camera, viewport: viewport, showsLabels: true)
        #expect(narrow.markers.count == 1)
        #expect(narrow.labels.first?.width == 8)
        #expect(narrow.labels.first?.column == 0)
        #expect(narrow.labels.first?.text == long.title)

        let outside = try MapMarker(id: "outside", coordinate: MapCoordinate(latitude: 0, longitude: 30), title: "Outside")
        #expect(MapMarkerPlacement(markers: [outside], selection: outside.id, camera: camera,
                                   viewport: viewport, showsLabels: true).markers.isEmpty)
    }

    @Test("A selected title reserves its cells before flanking marker glyphs even when labels are hidden")
    func selectedTitleBeforeFlankingMarkers() throws {
        let camera = try makeCamera()
        let viewport = try MapViewport(columns: 40, rows: 20)
        let selected = try MapMarker(id: "selected", coordinate: camera.center, title: "Selected")
        let right = try MapMarker(id: "right", coordinate: MapCoordinate(latitude: 0, longitude: 2.5), title: "Right")
        let left = try MapMarker(id: "left", coordinate: MapCoordinate(latitude: 0, longitude: -2.5), title: "Left")
        let beyond = try MapMarker(id: "beyond", coordinate: MapCoordinate(latitude: 0, longitude: 7), title: "Beyond")
        let placement = MapMarkerPlacement(markers: [right, left, selected, beyond], selection: selected.id,
                                            camera: camera, viewport: viewport, showsLabels: false)
        let label = try #require(placement.labels.first)
        #expect(placement.labels.count == 1)
        #expect(label.id == selected.id && label.text == selected.title)
        #expect(label.column == 23 && label.width == 8)
        #expect(Set(placement.markers.map(\.value.id)) == [selected.id, left.id, beyond.id])
        #expect(placement.markers.allSatisfy {
            $0.row != label.row || !(label.column..<(label.column + label.width)).contains($0.column)
        })
        #expect(placement.reservations.contains { $0 == label })
    }

    @Test("Marker symbols and names reserve space before optional geographic labels")
    func geographicReservations() throws {
        let camera = try makeCamera()
        let viewport = try MapViewport(columns: 40, rows: 20)
        let marker = try MapMarker(id: "marker", coordinate: camera.center, title: "Place")
        let placement = MapMarkerPlacement(markers: [marker], selection: marker.id,
                                            camera: camera, viewport: viewport, showsLabels: true)
        let candidates: [PreparedMap.Label] = [
            .init(featureID: "near", kind: .water, text: "Lake", position: .init(x: 22, y: 10)),
            .init(featureID: "far", kind: .park, text: "Elsewhere", position: .init(x: 5, y: 3)),
        ]
        let unreserved = MapLabels(candidates: candidates, columns: 40, rows: 20, enabled: true)
        #expect(Set(unreserved.labels.map(\.id)) == ["near", "far"])
        let reserved = MapLabels(candidates: candidates, columns: 40, rows: 20, enabled: true,
                                  reserved: placement.reservations)
        #expect(reserved.labels.map(\.id) == ["far"])
        #expect(placement.reservations.contains { $0.id == marker.id && $0.text.isEmpty && $0.width == 3 })
        #expect(placement.reservations.contains { $0.id == marker.id && $0.width == 5 })
    }

    @Test("Routes own their native cells and clear adjacent geography without changing area fills")
    func routePaintPriority() throws {
        let viewport = try MapViewport(columns: 10, rows: 10)
        let geography = PreparedMap.Line(featureID: "road", kind: .primaryRoad,
                                         points: [.init(x: 2, y: 4.1), .init(x: 8, y: 4.1)])
        let route = PreparedMap.Line(featureID: "route", kind: .primaryRoad,
                                    points: [.init(x: 4.6, y: 2), .init(x: 4.6, y: 8)])
        let land = PreparedMap.Polygon(featureID: "land", kind: .land, rings: [rectangle(0, 0, 10, 10)])
        for theme in [ChioTheme.default, .light, .btop] {
            let drawing = try MapDrawing(map: map(lines: [geography], polygons: [land]), viewport: viewport,
                                          colors: theme.colors, waterColor: theme.map.water,
                                          parkColor: theme.map.park, fills: true, routes: [route])
            let surface = render(drawing)
            let cell = surface.cells[4][4]
            let scalar = try #require(cell.character.unicodeScalars.first)
            #expect((0x2800...0x28FF).contains(scalar.value))
            let mask = scalar.value - 0x2800
            #expect(mask == 0xB8) // Only the route's right-column dots survive.
            #expect(surface.cells[4][5].character == "⠈") // One adjacent geography dot survives the halo.
            #expect(surface.cells[4][3].character == "⠉") // More distant geography remains intact.
            #expect(cell.style?.foregroundColor == theme.colors.accent)
            #expect(cell.style?.backgroundColor == theme.colors.selectedSurface)
            #expect(surface.cells[4][2].style?.foregroundColor == theme.colors.foreground)
            #expect(surface.cells[2][4].style?.foregroundColor == theme.colors.accent)
        }
    }

    @Test("Geography and routes consume one drawing allowance before native painting")
    func combinedDrawingAllowance() throws {
        let viewport = try MapViewport(columns: 240, rows: 100)
        func zigzag(_ segments: Int, id: String) -> PreparedMap.Line {
            .init(featureID: id, kind: .primaryRoad, points: (0...segments).map {
                .init(x: $0.isMultiple(of: 2) ? 0 : 240, y: 50)
            })
        }
        let geography = map(lines: [zigzag(259, id: "road")])
        let route = zigzag(260, id: "route")
        #expect(try MapDrawingWork(map: geography, viewport: viewport, fills: false).strokeSamples == 259 * 481)
        #expect(try MapDrawingWork(map: map(), viewport: viewport, fills: false, routes: [route]).strokeSamples == 260 * 481)
        #expect(try MapDrawingWork(map: geography, viewport: viewport, fills: false, routes: [route]).strokeSamples == 519 * 481)
        let excess = zigzag(261, id: "route")
        #expect(throws: MapValidationError.drawingBudgetExceeded) {
            try PreparedMapDrawing(map: geography, routes: [excess], viewport: viewport, fills: false)
        }
        #expect(throws: MapValidationError.drawingBudgetExceeded) {
            try MapDrawing(map: geography, viewport: viewport, colors: ChioTheme.default.colors,
                           waterColor: ChioTheme.default.map.water, parkColor: ChioTheme.default.map.park,
                           fills: false, routes: [excess])
        }
    }

    @Test("Selected Braille rings clip at edges and displace route dots only in their occupied cells")
    func brailleMarkerComposition() throws {
        let viewport = try MapViewport(columns: 10, rows: 6)
        let value = try MapMarker(id: "position", coordinate: MapCoordinate(latitude: 0, longitude: 0))
        let route = PreparedMap.Line(featureID: "route", kind: .primaryRoad,
                                    points: [PreparedMap.Point(x: 0, y: 3), PreparedMap.Point(x: 9.9, y: 3)])
        for point in [PreparedMap.Point(x: 5, y: 3), PreparedMap.Point(x: 0, y: 0),
                      PreparedMap.Point(x: 9.9, y: 5.9)] {
            let marker = MapMarkerPlacement.Marker(value: value, position: point, isSelected: true, viewport: viewport)
            #expect(marker.glyph.width <= 3 && marker.glyph.height <= 2)
            #expect(marker.origin.x >= 0 && marker.origin.y >= 0)
            #expect(marker.origin.x + marker.glyph.width <= viewport.columns)
            #expect(marker.origin.y + marker.glyph.height <= viewport.rows)
            if point.x == 5 {
                #expect(marker.glyph.cells.flatMap { $0 }.reduce(0) { $0 + $1.mask.nonzeroBitCount } == 13)
            }
            for theme in [ChioTheme.default, .light, .btop] {
                for fills in [false, true] {
                    let land = PreparedMap.Polygon(featureID: "land", kind: .land, rings: [rectangle(0, 0, 10, 6)])
                    let drawing = try MapDrawing(map: map(polygons: [land]), viewport: viewport, colors: theme.colors,
                                                  waterColor: theme.map.water, parkColor: theme.map.park,
                                                  fills: fills, routes: [route], markers: [marker])
                    let view = ZStack(alignment: .topLeading) {
                        Canvas(drawing, grid: .braille2x4)
                        Canvas(marker, grid: .braille2x4).foregroundStyle(theme.colors.warning)
                            .frame(width: marker.glyph.width, height: marker.glyph.height)
                            .offset(x: marker.origin.x, y: marker.origin.y)
                    }.frame(width: 10, height: 6).background(theme.colors.surface)
                    let raster = DefaultRenderer().render(view, proposal: ProposedSize(width: 10, height: 6)).rasterSurface
                    for y in 0..<marker.glyph.height {
                        for x in 0..<marker.glyph.width where marker.glyph.cell(x: x, y: y).mask != 0 {
                            let cell = raster.cells[marker.origin.y + y][marker.origin.x + x]
                            #expect(cell.character == marker.glyph.cell(x: x, y: y).glyph)
                            #expect(cell.style?.foregroundColor == theme.colors.warning)
                            #expect(cell.style?.backgroundColor == (fills ? theme.colors.selectedSurface : theme.colors.surface))
                        }
                    }
                    if point.x == 5 {
                        // No additional marker halo: the immediately adjacent route cell survives.
                        #expect(raster.cells[3][marker.origin.x - 1].character == "⠉")
                        #expect(raster.cells[3][marker.origin.x - 1].style?.foregroundColor == theme.colors.accent)
                    }
                }
            }
        }
        let ordinary = MapMarkerPlacement.Marker(value: value, position: PreparedMap.Point(x: 5, y: 3),
                                                  isSelected: false, viewport: viewport)
        #expect(ordinary.glyph.cell(x: 0, y: 0).mask == 0x36)
    }

    @Test("A selected ring reserves all of its rows before another marker or geographic label")
    func ringReservations() throws {
        let camera = try makeCamera()
        let viewport = try MapViewport(columns: 40, rows: 20)
        let selected = try MapMarker(id: "selected", coordinate: camera.center)
        let neighbor = try MapMarker(id: "neighbor", coordinate: MapCoordinate(latitude: 0.5, longitude: 0))
        let placement = MapMarkerPlacement(markers: [neighbor, selected], selection: selected.id,
                                            camera: camera, viewport: viewport, showsLabels: false)
        #expect(placement.markers.map(\.value.id) == [selected.id])
        #expect(Set(placement.reservations.map(\.row)) == [9, 10])
        #expect(placement.reservations.allSatisfy { $0.column == 19 && $0.width == 3 })
    }

    @Test("Geographic fills use map colors independently of syntax and theme replacement preserves other components")
    func geographicThemeColors() throws {
        let viewport = try MapViewport(columns: 10, rows: 10)
        let geography = map(polygons: [
            .init(featureID: "park", kind: .park, rings: [rectangle(0, 0, 10, 10)]),
            .init(featureID: "water", kind: .water, rings: [rectangle(2, 2, 8, 8)]),
        ])
        for theme in [ChioTheme.default, .light, .btop] {
            let syntax = theme.syntax.replacing(type: Color(hexRGB: 0xFF0000), string: Color(hexRGB: 0x00FF00))
            let changedSyntax = theme.replacing(syntax: syntax)
            #expect(changedSyntax.map == theme.map)
            let drawing = try MapDrawing(map: geography, viewport: viewport, colors: changedSyntax.colors,
                                          waterColor: changedSyntax.map.water, parkColor: changedSyntax.map.park, fills: true)
            let surface = render(drawing)
            #expect(surface.cells[1][1].style?.backgroundColor == theme.map.park)
            #expect(surface.cells[3][3].style?.backgroundColor == theme.map.water)
            #expect(surface.cells[3][3].style?.backgroundColor != syntax.type)
            #expect(surface.cells[1][1].style?.backgroundColor != syntax.string)

            let changedMap = theme.replacing(map: theme.map.replacing(water: Color(hexRGB: 0x123456)))
            #expect(changedMap.map.water == Color(hexRGB: 0x123456))
            #expect(changedMap.map.park == theme.map.park)
            #expect(changedMap.colors == theme.colors)
            #expect(changedMap.spacing == theme.spacing)
            #expect(changedMap.treatments == theme.treatments)
            #expect(changedMap.syntax == theme.syntax)
        }
    }

    private func makeCamera() throws -> MapCamera {
        try MapCamera(center: MapCoordinate(latitude: 0, longitude: 0), longitudeSpan: 20)
    }

    private func render(_ drawing: MapDrawing) -> RasterSurface {
        let view = Canvas(drawing).frame(width: drawing.viewport.columns, height: drawing.viewport.rows)
            .background(drawing.colors.surface)
        return DefaultRenderer().render(view, proposal: .init(width: drawing.viewport.columns,
                                                              height: drawing.viewport.rows)).rasterSurface
    }

    private func map(lines: [PreparedMap.Line] = [], polygons: [PreparedMap.Polygon] = []) -> PreparedMap {
        .init(lines: lines, polygons: polygons, labels: [],
              statistics: .init(sourceVertices: 0, preparedVertices: 0, visibleFeatures: 0))
    }

    private func rectangle(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> [PreparedMap.Point] {
        [.init(x: left, y: top), .init(x: right, y: top), .init(x: right, y: bottom),
         .init(x: left, y: bottom), .init(x: left, y: top)]
    }
}
