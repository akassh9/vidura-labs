//
//  Pythiainstaller.swift
//  Physics Companion
//
//  Created by Lorenzo P on 4/11/26.
//

import Foundation

enum PythiaInstaller {
    private static let pythiaVersion = "8.317"
    
    static func needsInstall() -> Bool {
        let versionFile = PathUtils.pythiaDir.appendingPathComponent(".version")
        guard let installed = try? String(contentsOf: versionFile, encoding: .utf8) else {
            return true
        }
        
        return installed.trimmingCharacters(in: .whitespacesAndNewlines) != pythiaVersion
    }
    
    static func markInstalled() throws {
        let versionFile = PathUtils.pythiaDir.appendingPathComponent(".version")
        print("Writing version file to: \(versionFile.path)")
        do {
            try pythiaVersion.write(to: versionFile, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to write version file: \(error)")
            throw error
        }
    }
    
    static func ensureReady(onProgress: (String) -> Void) throws {
        guard needsInstall() else { return }
        
        let src = PathUtils.bundledPythisDir
        let dst = PathUtils.pythiaDir
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: src.path) else {
            throw PythiaError.bundleFileMissing
        }
        
        onProgress("Creating directories...")
        try fm.createDirectory(at: dst.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dst.appendingPathComponent("include"),  withIntermediateDirectories: true)
        try fm.createDirectory(at: dst.appendingPathComponent("share"),    withIntermediateDirectories: true)
        try fm.createDirectory(at: PathUtils.simulationsDir,              withIntermediateDirectories: true)
        
        onProgress("Installing Pythia libraries...")
        try copyRecursively(from: src, to: dst)
        
        try markInstalled()
        onProgress("Done.")
    }
    
    private static func copyRecursively(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        try fm .createDirectory(at: dst, withIntermediateDirectories: true)
        
        for item in try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: [.isDirectoryKey]) {
            let dstItem = dst.appendingPathComponent(item.lastPathComponent)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)
            
            if isDir.boolValue {
                try copyRecursively(from: item, to: dstItem)
            } else {
                if fm.fileExists(atPath: dstItem.path) {
                    try fm.removeItem(at: dstItem)
                }
                try fm.copyItem(at: item, to: dstItem)
            }
        }
    }
}

enum PythiaError: LocalizedError {
    case bundleFileMissing
    
    var errorDescription: String? {
        switch self {
        case .bundleFileMissing:
            return "Bundled Pythia files missing from app bundle."
        }
    }
}
