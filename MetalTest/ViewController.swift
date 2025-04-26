//
//  ViewController.swift
//  MetalTest
//
//  Created by 杨学思 on 2025/2/23.
//

import UIKit
import Metal
import MetalKit
import Accelerate
import Spatial
import GLKit

struct Model {
    let vertex: [Vector3<Float>]
    let facesCount: Int
}

struct Matrix4x4<T> where T: SIMDScalar {
    // layout compatible with concrete SIMD types when T is float
    // or double, so you can unsafeBitcast to or from those types.
    var columns: (SIMD4<T>, SIMD4<T>, SIMD4<T>, SIMD4<T>)
}

struct Transform {
    let scale: Size3D
    let rotation: Rotation3D
    let translation: Vector3D
}

struct Instance {
    let modelIndex: Int
    let scale: simd_float3
    var rotation: GLKMatrix4
    let translation: simd_float3
    
    init(modelIndex: Int, scale: simd_float3, rotation: GLKMatrix4, translation: simd_float3) {
        self.modelIndex = modelIndex
        self.scale = scale
        self.rotation = rotation
        self.translation = translation
    }
}

struct Camera {
    let translate: Vector3D
    var rotate: Rotation3D
    let fov: Float
    let aspect: Float
    let near: Float
    let far: Float
    
    func view_transform() -> float4x4 {
        let affine = AffineTransform3D.init(rotation: rotate, translation: translate)
        return float4x4(affine)
    }

    func perspective_transform() -> float4x4 {
        let transform = ProjectiveTransform3D.init(fovY: Angle2D(degrees: fov), aspectRatio: Double(self.aspect), nearZ: Double(self.near), farZ: Double(self.far))
        return simd_float4x4(transform)
    }
}

// Vector3 struct to match the Rust implementation
struct Vector3<T> {
    var x: T
    var y: T
    var z: T
    
    init(x: T, y: T, z: T) {
        self.x = x
        self.y = y
        self.z = z
    }
}

struct Vector2<T> {
    var x: T
    var y: T
    
    init(x: T, y: T) {
        self.x = x
        self.y = y
    }
}

struct TextureCoord {
    var u: Float
    var v: Float
    
    init(u: Float, v: Float) {
        self.u = u
        self.v = v
    }
}

struct Face {
    let vertices: Vector3<Float>
    let textureCoord: Vector2<Float>
}

func parseObj(filePath: String) -> (faces: [Face], indices: [UInt16]) {
    var vertices: [Vector3<Float>] = []
    var texCoords: [TextureCoord] = []
    var faces: [Face] = []
    var indices: [UInt16] = []
    
    do {
        let fileContents = try String(contentsOfFile: filePath, encoding: .utf8)
        let lines = fileContents.components(separatedBy: .newlines)
        
        for line in lines {
            // 跳过空行和注释
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if components.isEmpty { continue }
            
            let identifier = components[0]
            
            // 处理顶点
            if identifier == "v" && components.count >= 4 {
                if let x = Float(components[1]),
                   let y = Float(components[2]),
                   let z = Float(components[3]) {
                    vertices.append(Vector3(x: x, y: y, z: z))
                }
            }
            // 处理纹理坐标
            else if identifier == "vt" && components.count >= 3 {
                if let u = Float(components[1]),
                   let v = Float(components[2]) {
                    texCoords.append(TextureCoord(u: u, v: v))
                }
            }
            // 处理面（三角形）
            else if identifier == "f" && components.count >= 4 {
                // 提取顶点索引和纹理坐标索引
                var vertexIndices: [Int] = []
                var uvIndices: [Int] = []
                
                for i in 1..<components.count {
                    let vertexData = components[i].components(separatedBy: "/")
                    
                    if let vertexIndex = Int(vertexData[0]) {
                        vertexIndices.append(vertexIndex - 1)
                    }
                    
                    if vertexData.count > 1 && !vertexData[1].isEmpty {
                        if let uvIndex = Int(vertexData[1]) {
                            uvIndices.append(uvIndex - 1)
                        }
                    } else {
                        uvIndices.append(-1)
                    }
                }
                
                // 处理三角形面
                if vertexIndices.count == 3 {
                    let v1 = vertices[vertexIndices[0]]
                    let v2 = vertices[vertexIndices[1]]
                    let v3 = vertices[vertexIndices[2]]
                    
                    let uv1 = uvIndices[0] >= 0 ? texCoords[uvIndices[0]] : TextureCoord(u: 0, v: 0)
                    let uv2 = uvIndices[1] >= 0 ? texCoords[uvIndices[1]] : TextureCoord(u: 0, v: 0)
                    let uv3 = uvIndices[2] >= 0 ? texCoords[uvIndices[2]] : TextureCoord(u: 0, v: 0)
                    
                    faces.append(Face(vertices: v1, textureCoord: Vector2(x: uv1.u, y: uv1.v)))
                    faces.append(Face(vertices: v2, textureCoord: Vector2(x: uv2.u, y: uv2.v)))
                    faces.append(Face(vertices: v3, textureCoord: Vector2(x: uv3.u, y: uv3.v)))
                    
                    indices.append(UInt16(faces.count - 3))
                    indices.append(UInt16(faces.count - 2))
                    indices.append(UInt16(faces.count - 1))
                }
                // 如果面是四边形或多边形，需要三角化
                else if vertexIndices.count > 3 {
                    for i in 1..<(vertexIndices.count - 1) {
                        let v1 = vertices[vertexIndices[0]]
                        let v2 = vertices[vertexIndices[i]]
                        let v3 = vertices[vertexIndices[i + 1]]
                        
                        let uv1 = uvIndices[0] >= 0 ? texCoords[uvIndices[0]] : TextureCoord(u: 0, v: 0)
                        let uv2 = uvIndices[i] >= 0 ? texCoords[uvIndices[i]] : TextureCoord(u: 0, v: 0)
                        let uv3 = uvIndices[i + 1] >= 0 ? texCoords[uvIndices[i + 1]] : TextureCoord(u: 0, v: 0)
                        
                        faces.append(Face(vertices: v1, textureCoord: Vector2(x: uv1.u, y: uv1.v)))
                        faces.append(Face(vertices: v2, textureCoord: Vector2(x: uv2.u, y: uv2.v)))
                        faces.append(Face(vertices: v3, textureCoord: Vector2(x: uv3.u, y: uv3.v)))
                        
                        indices.append(UInt16(faces.count - 3))
                        indices.append(UInt16(faces.count - 2))
                        indices.append(UInt16(faces.count - 1))
                    }
                }
            }
        }
    } catch {
        print("Error reading OBJ file: \(error)")
    }
    
    return (faces, indices)
}

func parseFile(filePath: String) -> (vertices: [Vector3<Float>], triangles: [Vector3<Int>]) {
    var vertices: [Vector3<Float>] = []
    var triangles: [Vector3<Int>] = []
    var phase = 0
    var verticesCount = 0
    var trianglesCount = 0
    
    do {
        let fileContents = try String(contentsOfFile: filePath, encoding: .utf8)
        let lines = fileContents.components(separatedBy: .newlines)
        
        for line in lines {
            let parts = line.split(separator: " ")
            
            if phase == 0 {
                if let first = parts.first {
                    if first == "end_header" {
                        phase = 1
                    } else if first == "element" {
                        let element = String(parts[1])
                        let count = Int(parts[2])!
                        
                        if element == "vertex" {
                            verticesCount = count
                        } else if element == "face" {
                            trianglesCount = count
                        }
                    }
                }
            } else if phase == 1 {
                if parts.count >= 3 {
                    let x = Float(parts[0])!
                    let y = Float(parts[1])!
                    let z = Float(parts[2])!
                    vertices.append(Vector3(x: x, y: y, z: z))
                    
                    if vertices.count == verticesCount {
                        phase = 2
                    }
                }
            } else if phase == 2 {
                if parts.count >= 4 { // First value is vertex count (usually 3)
                    let x = Int(parts[1])!
                    let y = Int(parts[2])!
                    let z = Int(parts[3])!
                    triangles.append(Vector3(x: x, y: y, z: z))
                    
                    if triangles.count == trianglesCount {
                        break
                    }
                }
            }
        }
    } catch {
        print("Error reading file: \(error)")
        return ([], [])
    }
    
    return (vertices, triangles)
}

extension simd_float4x4 {
    static let identity = simd_float4x4(.init(1, 0, 0, 0), .init(x: 0, y: 1, z: 0, w: 0), .init(x: 0, y: 0, z: 1, w: 0), .init(x: 0, y: 0, z: 0, w: 1))
}

class ViewController: UIViewController {
    let mtkView: MTKView
    var models: [Model] = []
    
    var instance: [Instance] = []
    
    var instanceBuffer: MTLBuffer?
    
    var commandBuffer: MTLCommandBuffer?
    
    var renderPassDesc: MTLRenderPassDescriptor?
    
    var texture: MTLTexture?
    
    required init?(coder: NSCoder) {
        let device = MTLCreateSystemDefaultDevice()!
        self.mtkView = MTKView(frame: .zero, device: device)
        super.init(coder: coder)
    }
    
    private var renderPipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    private var indexBuffer: MTLBuffer!
    private var uniformsBuffer: MTLBuffer!
    private var camera: Camera!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.addSubview(mtkView)
        mtkView.frame = self.view.bounds
        mtkView.delegate = self
        
        instanceBuffer = mtkView.device?.makeBuffer(length: MemoryLayout<Instance>.size * 1024)
        let empty = Instance(modelIndex: 0, scale: .zero, rotation: GLKMatrix4Identity, translation: .zero)
        instance.append(.init(modelIndex: 0, scale: simd_float3.init(x: 1, y: 1, z: 1) * 2, rotation: GLKMatrix4Identity, translation: .zero))
        let ptr = instanceBuffer?.contents()
        let buffer = UnsafeMutableBufferPointer(start: ptr!.assumingMemoryBound(to: Instance.self), count: 1024)
        buffer.initialize(repeating: empty)
        for (idx, item) in instance.enumerated() {
            buffer[idx] = item
        }
        
        setupView()
        setupCamera()
        setupBuffers()
        setupRenderPipeline()
        
        guard let device = mtkView.device,
              let commandQueue = device.makeCommandQueue() else {
            return
        }
        
        let loader = MTKTextureLoader(device: device)
        
        texture = try! loader.newTexture(URL: Bundle.main.url(forResource: "WOLF", withExtension: "TIF")!, options: nil)
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        
        // 配置color attachment，使用MTKView的currentDrawable的texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        self.renderPassDesc = renderPassDescriptor
        self.commandQueue = commandQueue
    }
    
    var commandQueue: MTLCommandQueue?
    
    private func setupView() {
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.colorPixelFormat = .bgra8Unorm
    }
    
    private func setupCamera() {
        camera = Camera(
            translate: Vector3D(x: 0, y: 0, z: -10),
            rotate: Rotation3D.identity,
            fov: 60.0,
            aspect: Float(mtkView.bounds.width / mtkView.bounds.height),
            near: 0.1,
            far: 100.0
        )
    }
    
    private func setupBuffers() {
        guard let device = mtkView.device,
              let file = Bundle.main.path(forResource: "WOLF", ofType: "OBJ") else { return }
        
        let (vertices, faces) = parseObj(filePath: file)
        let model = Model(vertex: [], facesCount: faces.count)
        models.append(model)
        
        // 创建顶点缓冲
//        let vertexData = vertices.map { SIMD8<Float>($0.vertices.x, $0.vertices.y, $0.vertices.z, $0.textureCoord.x, $0.textureCoord.y, 0, 0, 0) }
        let vertexData = vertices.map { simd_float2x3(SIMD3<Float>.init($0.vertices.x, $0.vertices.y, $0.vertices.z), .init($0.textureCoord.x, $0.textureCoord.y, 0)) }
        vertexBuffer = device.makeBuffer(bytes: vertexData,
                                         length: MemoryLayout<simd_float2x3>.stride * vertices.count,
                                         options: .storageModeShared)
        
        indexBuffer = device.makeBuffer(bytes: faces,
                                        length: MemoryLayout<UInt16>.stride * faces.count,
                                        options: .storageModeShared)
        
        // 创建 Uniforms 缓冲
        uniformsBuffer = device.makeBuffer(length: MemoryLayout<float4x4>.stride * 2,
                                           options: .storageModeShared)
    }
    
    private func setupRenderPipeline() {
        guard let device = mtkView.device,
              let library = device.makeDefaultLibrary() else { return }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        
        // 设置顶点描述符
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<simd_float3>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<simd_float2x3>.stride
        
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        // 设置颜色附件
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create render pipeline state: \(error)")
        }
    }
    
    func draw(in view: MTKView) {
//        guard let renderPassDesc else {
//            return
//        }
        guard let commandQueue = commandQueue else {
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
//        if let drawable = view.currentDrawable {
//            renderPassDesc.colorAttachments[0].texture = drawable.texture
//        }
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: view.currentRenderPassDescriptor!) else {
            return
        }

        
        instance[0].rotation = GLKMatrix4RotateY(instance[0].rotation, 1 / 360)
        
        let ptr = self.instanceBuffer?.contents()
        
        let buffer = UnsafeMutableBufferPointer(start: ptr!.assumingMemoryBound(to: Instance.self), count: 1024)
        for (idx, item) in instance.enumerated() {
            buffer[idx] = item
        }
        
        // 更新 uniform 缓冲
        let uniformsContents = uniformsBuffer.contents().assumingMemoryBound(to: float4x4.self)
        uniformsContents[0] = camera.view_transform()
        uniformsContents[1] = camera.perspective_transform()
        
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
        renderEncoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 2)
        renderEncoder.setFragmentTexture(texture, index: 0)
//        renderEncoder.setTriangleFillMode(.lines)
        renderEncoder.setCullMode(.back)
        
        // 绘制实例
        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: models[0].facesCount,
                                            indexType: .uint16,
                                            indexBuffer: indexBuffer,
                                            indexBufferOffset: 0,
                                            instanceCount: instance.count)
        
        renderEncoder.endEncoding()
        
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        
        commandBuffer.commit()
    }
    
//    override func viewDidLoad() {
//        super.viewDidLoad()
//        
//        let file = Bundle.main.path(forResource: "cube", ofType: "ply")!
//        let (vertex, faces) = parseFile(filePath: file)
//        let model = Model(vertex: vertex, faces: faces)
//        self.view.addSubview(mtkView)
//        mtkView.frame = self.view.bounds
//        mtkView.delegate = self
//        
//        instance.append(.init(modelIndex: 0, transform: .init(scale: .init(width: 1.0, height: 1.0, depth: 1.0), rotation: Rotation3D.identity, translation: .init(x: 0.0, y: 0.0, z: 0.0))))
//        
//        print(mtkView.device)
//        
//        guard let device = mtkView.device else {
//            return
//        }
//        
//        let queue = device.makeCommandQueue()!
//        let commandBuffer = queue.makeCommandBuffer()!
//        self.commandBuffer = commandBuffer
//        
//        let library = device.makeDefaultLibrary()
//        let desc = MTLRenderPassDescriptor()
//        
//        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc)
//        for (idx, model) in models.enumerated() {
//            let vertexBuffer = device.makeBuffer(length: MemoryLayout<Vector3<Float>>.size * model.vertex.count)
//            encoder?.setVertexBuffer(vertexBuffer, offset: 0, index: idx)
//        }
//        instanceBuffer = device.makeBuffer(length: MemoryLayout<Instance>.size * 1024)
//        let ptr = instanceBuffer?.contents()
//        let buffer = UnsafeMutableBufferPointer(start: ptr!.assumingMemoryBound(to: Instance.self), count: 1024)
//        buffer.initialize(repeating: Instance(modelIndex: 0, transform: .identity))
//        for (idx, item) in instance.enumerated() {
//            buffer[idx] = item
//        }
//        encoder?.endEncoding()
//        
//        commandBuffer.commit()
//        commandBuffer.waitUntilCompleted()
////        let instanceBuffer = instance.withUnsafeBufferPointer { ptr in
////            return device.makeBuffer(bytes: ptr.baseAddress!, length: ptr.count)
////        }
//        // Do any additional setup after loading the view.
//    }
}

extension ViewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }
}

