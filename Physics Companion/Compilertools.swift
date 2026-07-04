//
//  Compilertools.swift
//  Physics Companion
//
//  Created by Lorenzo P on 4/11/26.
//

import Foundation

enum CompilerTools {
    static func needsCompilerInstall() -> Bool {
        // Check if clang++ exists directly instead of going through xcrun
        // (xcrun cannot be used inside an App Sandbox)
        return !FileManager.default.isExecutableFile(atPath: "/usr/bin/clang++")
    }
    
    static func ensureCompiler() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/clang++") else {
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/xcode-select"), arguments: ["--install"])
            throw CompilerError.cltNotInstalled
        }
    }
    
    @discardableResult
    static func buildSimulation(simId: String, onProgress: @escaping (String) -> Void) throws -> URL {
        let pythia = PathUtils.pythiaDir
        let simDir = PathUtils.simulationsDir
        let outputBin = simDir.appendingPathComponent("simulation")
        
        let args: [String] = [
            "-std=c++17",
            "-I\(pythia.appendingPathComponent("include").path)",
            "main.cc",
            "-I\(simDir.appendingPathComponent("lib").path)",
            pythia.appendingPathComponent("lib/libpythia8.a").path,
            "-ldl",
            "-lz",
            "-DPYTHIA8DATA=\"\(pythia.appendingPathComponent("share/Pythia8/xmldoc").path)\"",
            "-o", outputBin.path,
        ]
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/clang++")
        process.arguments     = args
        process.currentDirectoryURL = simDir
        
        let pipe = Pipe()
        process.standardError  = pipe
        process.standardOutput = pipe

        try process.run()
        
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            text.components(separatedBy: .newlines)
                .filter{!$0.isEmpty}
                .forEach{onProgress($0)}
        }
        
        process.waitUntilExit()
        handle.readabilityHandler = nil
        
        guard process.terminationStatus == 0 else {
            throw CompilerError.compilationFailed
        }
        
        return outputBin
    }
}

enum CompilerError: LocalizedError {
    case cltNotInstalled
    case compilationFailed
    
    var errorDescription: String? {
        switch self {
        case .cltNotInstalled:
            return "Please complete Xcode Command Line Tools installation and relaunch."
        case .compilationFailed:
            return "Compilation failed."
        }
    }
}

