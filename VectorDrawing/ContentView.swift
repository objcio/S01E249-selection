//
//  ContentView.swift
//  VectorDrawing
//
//  Created by Chris Eidhof on 22.02.21.
//

import SwiftUI

struct PathPoint: View {
    @Binding var element: Drawing.Element
    var isSelected: Bool
    var drawControlPoints: Bool
    var onClick: (_ shiftPressed: Bool) -> ()
    var move: (_ to: CGPoint) -> ()
    
    func pathPoint(at: CGPoint) -> some View {
        let drag = DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { state in
                move(state.location)
            }
        let optionDrag = DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .modifiers(.option)
            .onChanged { state in
                element.setCoupledControlPoints(to: state.location)
            }
        let doubleClick = TapGesture(count: 2)
            .onEnded {
                element.resetControlPoints()
            }
        let click = TapGesture(count: 1)
            .onEnded { onClick(false) }
        let shiftClick = TapGesture(count: 1)
            .modifiers(.shift)
            .onEnded { onClick(true) }
        let gesture = (shiftClick.exclusively(before: click)).simultaneously(with: doubleClick.simultaneously(with: optionDrag.exclusively(before: drag)))
        return Circle()
            .stroke(isSelected ? Color.blue : .black, lineWidth: isSelected ? 2 : 1)
            .background(Circle().fill(Color.white))
            .padding(2)
            .frame(width: 14, height: 14)
            .offset(x: at.x-7, y: at.y-7)
            .gesture(gesture)
    }

    func controlPoint(at: CGPoint, onDrag: @escaping (CGPoint, _ option: Bool) -> ()) -> some View {
        let drag = DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { state in
                onDrag(state.location, false)
            }
        let optionDrag = DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .modifiers(.option)
            .onChanged { state in
                onDrag(state.location, true)
            }
        let gesture = optionDrag.exclusively(before: drag)
        return RoundedRectangle(cornerRadius: 2)
            .stroke(Color.black)
            .background(RoundedRectangle(cornerRadius: 2).fill(Color.white))
            .padding(4)
            .frame(width: 14, height: 14)
            .offset(x: at.x-7, y: at.y-7)
            .gesture(gesture)
    }

    var body: some View {
        if drawControlPoints, let cp = element.controlPoints {
            Path { p in
                p.move(to: cp.0)
                p.addLine(to: element.point)
                p.addLine(to: cp.1)
            }.stroke(Color.gray)
            controlPoint(at: cp.0, onDrag: { element.moveControlPoint1(to: $0, option: $1) })
            controlPoint(at: cp.1, onDrag: { element.moveControlPoint2(to: $0, option: $1) })
        }
        pathPoint(at: element.point)
    }
}

struct Points: View {
    @Binding var drawing: Drawing
    
    var body: some View {
        let lastID = drawing.elements.last?.id
        ForEach(Array(zip(drawing.elements, drawing.elements.indices)), id: \.0.id) { element in
            let id = element.0.id
            let isSelected = drawing.selection.contains(id)
            let onClick: (Bool) -> () = { shiftPressed in
                drawing.select(id, shiftPressed: shiftPressed)
            }
            let move: (CGPoint) -> () = { point in
                if !isSelected {
                    drawing.select(id, shiftPressed: false)
                }
                drawing.move(id: id, to: point)
            }
            let drawControlPoints = isSelected || drawing.selection.isEmpty && id == lastID
            PathPoint(element: $drawing.elements[element.1], isSelected: isSelected, drawControlPoints: drawControlPoints, onClick: onClick, move: move)
        }
    }
}

struct Drawing {
    var elements: [Element] = []
    var selection: Set<Drawing.Element.ID> = []

    struct Element: Identifiable {
        let id = UUID()
        var point: CGPoint {
            didSet { point = point.rounded() }
        }
        var _primaryPoint: CGPoint? {
            didSet { _primaryPoint = _primaryPoint?.rounded() }
        }
        var secondaryPoint: CGPoint? {
            didSet { secondaryPoint = secondaryPoint?.rounded() }
        }

        var primaryPoint: CGPoint? {
            _primaryPoint ?? secondaryPoint?.mirrored(relativeTo: point)
        }
        
        init(point: CGPoint, secondaryPoint: CGPoint?) {
            self.point = point.rounded()
            self.secondaryPoint = secondaryPoint?.rounded()
        }
    }
}

extension Drawing.Element {
    var controlPoints: (CGPoint, CGPoint)? {
        guard let s = secondaryPoint, let p = primaryPoint else { return nil }
        return (p, s)
    }
    
    mutating func move(to: CGPoint) {
        let diff = to - point
        point = to
        _primaryPoint = _primaryPoint.map { $0 + diff }
        secondaryPoint = secondaryPoint.map { $0 + diff }
    }
    
    mutating func move(by amount: CGPoint) {
        move(to: point + amount)
    }
    
    mutating func moveControlPoint1(to: CGPoint, option: Bool) {
        if option || _primaryPoint != nil {
            _primaryPoint = to
        } else {
            secondaryPoint = to.mirrored(relativeTo: point)
        }
    }
    
    mutating func moveControlPoint2(to: CGPoint, option: Bool) {
        if option && _primaryPoint == nil {
            _primaryPoint = primaryPoint
        }
        secondaryPoint = to
    }
    
    mutating func resetControlPoints() {
        _primaryPoint = nil
        secondaryPoint = nil
    }
    
    mutating func setCoupledControlPoints(to: CGPoint) {
        _primaryPoint = nil
        secondaryPoint = to
    }
}

extension Drawing {
    var path: Path {
        var result = Path()
        guard let f = elements.first else { return result }
        result.move(to: f.point)
        var previousControlPoint: CGPoint? = nil
        
        for element in elements.dropFirst() {
            if let previousCP = previousControlPoint {
                let cp2 = element.controlPoints?.0 ?? element.point
                result.addCurve(to: element.point, control1: previousCP, control2: cp2)
            } else {
                if let mirrored = element.controlPoints?.0 {
                    result.addQuadCurve(to: element.point, control: mirrored)
                } else {
                    result.addLine(to: element.point)
                }
            }
            previousControlPoint = element.secondaryPoint
        }
        return result
    }

    mutating func update(for state: DragGesture.Value) {
        let isDrag = state.startLocation.distance(to: state.location) > 1
        elements.append(Element(point: state.startLocation, secondaryPoint: isDrag ? state.location : nil))
    }
    
    mutating func select(_ id: Element.ID, shiftPressed: Bool) {
        if shiftPressed {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        } else {
            selection = [id]
        }
    }
    
    subscript(id: Element.ID) -> Element {
        get {
            elements.first { $0.id == id }!
        }
        set {
            let idx = elements.indices.first { elements[$0].id == id }!
            elements[idx] = newValue
        }
    }
    
    mutating func move(id: Element.ID, to: CGPoint) {
        let currentEl = elements.first { $0.id == id }!
        let rel = to - currentEl.point
        for id in selection {
            self[id].move(by: rel)
        }
    }
}

struct DrawingView: View {
    @Binding var drawing: Drawing
    @GestureState var currentDrag: DragGesture.Value? = nil
    
    var liveDrawing: Drawing {
        var copy = drawing
        if let state = currentDrag {
            copy.update(for: state)
        }
        return copy
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            liveDrawing.path.stroke(Color.black, lineWidth: 2)
            Points(drawing: Binding(get: { liveDrawing }, set: { drawing = $0 }))
        }.gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($currentDrag, body: { (value, state, _) in
                    state = value
                })
                .onEnded { state in
                    drawing.update(for: state)
                }
        )
    }
}

struct ContentView: View {
    @State var drawing = Drawing()
    
    var body: some View {
        VStack {
            DrawingView(drawing: $drawing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView {
                Group {
                    if #available(macOS 11, *) {
                        TextEditor(text: .constant(drawing.path.code))
                    } else {
                        Text(drawing.path.code)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: 150)
        }
    }
}

extension CGPoint {
    var code: String {
        return "CGPoint(x: \(x), y: \(y))"
    }
}

extension Path.Element {
    var code: String {
        switch self {
        case .move(to: let to):
            return "p.move(to: \(to.code))"
        case .line(to: let to):
            return "p.addLine(to: \(to.code))"
        case .quadCurve(to: let to, control: let control):
            return "p.addQuadCurve(to: \(to.code), control: \(control.code))"
        case .curve(to: let to, control1: let control1, control2: let control2):
            return "p.addCurve(to: \(to.code), control1: \(control1.code), control2: \(control2.code))"
        case .closeSubpath:
            return "p.closeSubpath()"
        }
    }
}

extension Path {
    var code: String {
        guard !isEmpty else { return "Path()" }
        var result = "Path { p in \n"
        forEach { el in
            result.append("    \(el.code)\n")
        }
        result.append("}")
        return result
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
