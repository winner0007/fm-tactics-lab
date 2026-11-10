import AppKit

let folder = URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=size*scale
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        let transform=AffineTransform(scale:Double(pixels)/1024)
        (transform as NSAffineTransform).concat()
        NSColor(calibratedRed:0.10,green:0.27,blue:0.22,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:48,y:48,width:928,height:928),xRadius:205,yRadius:205).fill()
        NSColor.white.withAlphaComponent(0.24).setStroke()
        let pitch=NSBezierPath(rect:NSRect(x:235,y:176,width:554,height:672)); pitch.lineWidth=9; pitch.stroke()
        let circle=NSBezierPath(ovalIn:NSRect(x:409,y:409,width:206,height:206)); circle.lineWidth=8; circle.stroke()
        let mid=NSBezierPath(); mid.move(to:NSPoint(x:235,y:512)); mid.line(to:NSPoint(x:789,y:512)); mid.lineWidth=8; mid.stroke()
        let movement=NSBezierPath(); movement.move(to:NSPoint(x:370,y:340)); movement.line(to:NSPoint(x:630,y:535)); movement.line(to:NSPoint(x:490,y:731)); movement.line(to:NSPoint(x:495,y:650)); movement.move(to:NSPoint(x:490,y:731)); movement.line(to:NSPoint(x:568,y:702)); movement.lineWidth=22; movement.lineJoinStyle = .round; movement.lineCapStyle = .round
        NSColor(calibratedRed:0.86,green:0.94,blue:0.56,alpha:1).setStroke(); movement.stroke()
        for point in [NSPoint(x:370,y:340),NSPoint(x:630,y:535)] { NSColor.white.setFill(); NSBezierPath(ovalIn:NSRect(x:point.x-45,y:point.y-45,width:90,height:90)).fill() }
        NSGraphicsContext.restoreGraphicsState()
        let name="icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name))
    }
}
