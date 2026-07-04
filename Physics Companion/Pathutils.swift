//
//  Pathutils.swift
//  Physics Companion
//
//  Created by Lorenzo P on 4/11/26.
//

import Foundation

enum PathUtils {
    
    static var appSupportDir: URL {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not determine Application Support directory")
        }
        
        return base.appendingPathComponent("com.AL.PhysicsCompanion", isDirectory: true)
    }
    
    static var pythiaDir: URL {
        appSupportDir.appendingPathComponent("pythia", isDirectory: true)
    }
    
    static var simulationsDir: URL {
        appSupportDir.appendingPathComponent("simulations", isDirectory: true)
    }
    
    static var settingsDbPath: URL {
        appSupportDir.appendingPathComponent("settings.db")
    }
    
    static var researchDbPath: URL {
        appSupportDir.appendingPathComponent("research.db")
    }
    
    static var bundledPythisDir: URL {
        if let bundleURL = Bundle.main.url(forResource: "pythia_dist", withExtension: nil) {
            return bundleURL
        }
        
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        
        print(sourceRoot)
        
        return sourceRoot
            .appendingPathComponent("resources", isDirectory: true)
            .appendingPathComponent("pythia_dist", isDirectory: true)
    }
}
