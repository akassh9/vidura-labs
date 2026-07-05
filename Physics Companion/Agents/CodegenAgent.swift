//
//  CodegenAgent.swift
//  Physics Companion
//
//  Deterministic C++ code generator from SimulationSpec.
//

import Foundation

enum CodegenAgent {

    // MARK: - Run

    /// Generates a complete Pythia8 C++ program from a SimulationSpec.
    static func run(spec: SimulationSpec) -> GeneratedCode {
        // Compute frame_type
        let frameType: Int
        switch spec.beams.frameType.lowercased() {
        case "pp": frameType = 1
        case "ee": frameType = 1
        case "ep": frameType = 2
        default:   frameType = 1
        }

        // Build settings lines
        var settings: [String] = []
        settings.append("Random:setSeed = on")
        settings.append("Random:seed = \(spec.seed)")
        settings.append("Beams:frameType = \(frameType)")
        settings.append("Beams:eCM = \(spec.beams.eCmGev)")
        settings.append(contentsOf: spec.processSettings)
        settings.append(contentsOf: spec.cutsSettings)

        // Determine family
        let family = AnalysisFamily(rawValue: spec.analysisPlan?.family ?? "charged_multiplicity")
            ?? .chargedMultiplicity

        // Generate source
        let source = generateSource(
            settings: settings,
            family: family,
            eventCount: spec.eventCount,
            extraFiles: spec.outputPlan.extraFiles
        )

        return GeneratedCode(
            sourceCode: source,
            commandFile: nil,
            origin: "deterministic"
        )
    }

    // MARK: - Source Generation

    private static func generateSource(
        settings: [String],
        family: AnalysisFamily,
        eventCount: Int,
        extraFiles: [String]
    ) -> String {
        let includes = """
        #include <cmath>
        #include <fstream>
        #include <iostream>
        #include <map>
        #include <string>
        #include <vector>
        #include "Pythia8/Pythia.h"
        """

        let settingsCode = settings.map {
            "    pythia.readString(\"\($0)\");"
        }.joined(separator: "\n")

        let analysisCode = sourceForFamily(family)
        let secondaryCode = secondaryCode(for: extraFiles, primaryFamily: family)

        return """
        \(includes)

        using namespace Pythia8;

        int main() {
            Pythia pythia;

        \(settingsCode)

            pythia.init();

            int generatedEvents = 0;
        \(analysisCode.declarations)
        \(secondaryCode.declarations)

            for (int iEvent = 0; iEvent < \(eventCount); ++iEvent) {
                if (!pythia.next()) continue;
                ++generatedEvents;
        \(analysisCode.eventLoop)
        \(secondaryCode.eventLoop)
            }

        \(analysisCode.finalize)
        \(secondaryCode.finalize)

            // Write summary_lines.txt
            std::ofstream summary("summary_lines.txt");
            summary << "generated_events=" << generatedEvents << std::endl;
        \(analysisCode.summaryLines)
        \(secondaryCode.summaryLines)
            summary.close();

        \(analysisCode.extraOutput)
        \(secondaryCode.extraOutput)

            pythia.stat();
            return 0;
        }
        """
    }

    // MARK: - Family-Specific Code

    private struct FamilyCode {
        let declarations: String
        let eventLoop: String
        let finalize: String
        let summaryLines: String
        let extraOutput: String
    }

    private static func sourceForFamily(_ family: AnalysisFamily) -> FamilyCode {
        switch family {
        case .chargedMultiplicity:
            return chargedMultiplicityCode()
        case .ptSpectrum:
            return ptSpectrumCode()
        case .etaRapidity:
            return etaRapidityCode()
        case .invariantMass:
            return invariantMassCode()
        case .pidYields:
            return pidYieldsCode()
        case .eventScalars:
            return eventScalarsCode()
        }
    }

    private static func secondaryCode(for extraFiles: [String], primaryFamily: AnalysisFamily) -> FamilyCode {
        var declarations: [String] = []
        var eventLoop: [String] = []
        var summaryLines: [String] = []
        var extraOutput: [String] = []

        if extraFiles.contains("hist_pt.txt"), primaryFamily != .ptSpectrum {
            declarations.append("""
                Hist secondaryPtHist("pT spectrum", 80, 0.0, 200.0);
                double secondaryPtTotal = 0.0;
                int secondaryPtCount = 0;
            """)
            eventLoop.append("""
                    for (int i = 0; i < pythia.event.size(); ++i) {
                        if (pythia.event[i].isFinal() && pythia.event[i].isCharged()) {
                            double pT = pythia.event[i].pT();
                            secondaryPtHist.fill(pT);
                            secondaryPtTotal += pT;
                            ++secondaryPtCount;
                        }
                    }
            """)
            summaryLines.append("""
                summary << "mean_pt=" << (secondaryPtCount > 0 ? secondaryPtTotal / secondaryPtCount : 0) << std::endl;
            """)
            extraOutput.append("""
                std::ofstream histPtFile("hist_pt.txt");
                secondaryPtHist.table(histPtFile, false, false);
                histPtFile.close();
            """)
        }

        if extraFiles.contains("hist_eta.txt"), primaryFamily != .etaRapidity {
            declarations.append("""
                Hist secondaryEtaHist("eta distribution", 80, -8.0, 8.0);
                double secondaryEtaAbsTotal = 0.0;
                int secondaryEtaCount = 0;
            """)
            eventLoop.append("""
                    for (int i = 0; i < pythia.event.size(); ++i) {
                        if (pythia.event[i].isFinal() && pythia.event[i].isCharged()) {
                            double eta = pythia.event[i].eta();
                            secondaryEtaHist.fill(eta);
                            secondaryEtaAbsTotal += std::abs(eta);
                            ++secondaryEtaCount;
                        }
                    }
            """)
            summaryLines.append("""
                summary << "mean_abs_eta=" << (secondaryEtaCount > 0 ? secondaryEtaAbsTotal / secondaryEtaCount : 0) << std::endl;
            """)
            extraOutput.append("""
                std::ofstream histEtaFile("hist_eta.txt");
                secondaryEtaHist.table(histEtaFile, false, false);
                histEtaFile.close();
            """)
        }

        if extraFiles.contains("hist_multiplicity.txt"), primaryFamily != .chargedMultiplicity {
            declarations.append("""
                Hist secondaryChargedHist("charged multiplicity", 100, -0.5, 799.5);
                double secondaryChargedTotal = 0.0;
            """)
            eventLoop.append("""
                    int secondaryNCharged = 0;
                    for (int i = 0; i < pythia.event.size(); ++i) {
                        if (pythia.event[i].isFinal() && pythia.event[i].isCharged())
                            ++secondaryNCharged;
                    }
                    secondaryChargedTotal += secondaryNCharged;
                    secondaryChargedHist.fill(secondaryNCharged);
            """)
            summaryLines.append("""
                summary << "mean_charged=" << (generatedEvents > 0 ? secondaryChargedTotal / generatedEvents : 0) << std::endl;
            """)
            extraOutput.append("""
                std::ofstream histMultiplicityFile("hist_multiplicity.txt");
                secondaryChargedHist.table(histMultiplicityFile, false, false);
                histMultiplicityFile.close();
            """)
        }

        return FamilyCode(
            declarations: declarations.joined(separator: "\n"),
            eventLoop: eventLoop.joined(separator: "\n"),
            finalize: "",
            summaryLines: summaryLines.joined(separator: "\n"),
            extraOutput: extraOutput.joined(separator: "\n")
        )
    }

    // MARK: charged_multiplicity

    private static func chargedMultiplicityCode() -> FamilyCode {
        FamilyCode(
            declarations: """
                Hist chargedHist("charged multiplicity", 100, -0.5, 799.5);
                double chargedTotal = 0.0;
            """,
            eventLoop: """
                    int nCharged = 0;
                    for (int i = 0; i < pythia.event.size(); ++i) {
                        if (pythia.event[i].isFinal() && pythia.event[i].isCharged())
                            ++nCharged;
                    }
                    chargedTotal += nCharged;
                    chargedHist.fill(nCharged);
            """,
            finalize: "",
            summaryLines: """
                summary << "mean_charged=" << (generatedEvents > 0 ? chargedTotal / generatedEvents : 0) << std::endl;
            """,
            extraOutput: """
                // Write hist_primary.txt
                std::ofstream histFile("hist_primary.txt");
                chargedHist.table(histFile, false, false);
                histFile.close();
            """
        )
    }

    // MARK: pt_spectrum

    private static func ptSpectrumCode() -> FamilyCode {
        FamilyCode(
            declarations: """
                Hist ptHist("pT spectrum", 80, 0.0, 200.0);
                double ptTotal = 0.0;
                int ptCount = 0;
            """,
            eventLoop: """
                    for (int i = 0; i < pythia.event.size(); ++i) {
                        if (pythia.event[i].isFinal() && pythia.event[i].isCharged()) {
                            double pT = pythia.event[i].pT();
                            ptHist.fill(pT);
                            ptTotal += pT;
                            ++ptCount;
                        }
                    }
            """,
            finalize: "",
            summaryLines: """
                summary << "mean_pt=" << (ptCount > 0 ? ptTotal / ptCount : 0) << std::endl;
            """,
            extraOutput: """
                // Write hist_primary.txt
                std::ofstream histFile("hist_primary.txt");
                ptHist.table(histFile, false, false);
                histFile.close();
            """
        )
    }

    // MARK: eta_rapidity

    private static func etaRapidityCode() -> FamilyCode {
        FamilyCode(
            declarations: """
                Hist etaHist("eta distribution", 80, -8.0, 8.0);
                double etaAbsTotal = 0.0;
                int etaCount = 0;
            """,
            eventLoop: """
                    for (int i = 0; i < pythia.event.size(); ++i) {
                        if (pythia.event[i].isFinal() && pythia.event[i].isCharged()) {
                            double eta = pythia.event[i].eta();
                            etaHist.fill(eta);
                            etaAbsTotal += std::abs(eta);
                            ++etaCount;
                        }
                    }
            """,
            finalize: "",
            summaryLines: """
                summary << "mean_abs_eta=" << (etaCount > 0 ? etaAbsTotal / etaCount : 0) << std::endl;
            """,
            extraOutput: """
                // Write hist_primary.txt
                std::ofstream histFile("hist_primary.txt");
                etaHist.table(histFile, false, false);
                histFile.close();
            """
        )
    }

    // MARK: invariant_mass

    private static func invariantMassCode() -> FamilyCode {
        FamilyCode(
            declarations: """
                Hist massHist("dimuon invariant mass", 80, 0.0, 200.0);
                int dimuonPairs = 0;
            """,
            eventLoop: """
                    std::vector<int> muonIndices;
                    for (int i = 0; i < pythia.event.size(); ++i) {
                        if (pythia.event[i].isFinal() && pythia.event[i].idAbs() == 13)
                            muonIndices.push_back(i);
                    }
                    for (size_t a = 0; a < muonIndices.size(); ++a) {
                        for (size_t b = a + 1; b < muonIndices.size(); ++b) {
                            Vec4 pSum = pythia.event[muonIndices[a]].p()
                                      + pythia.event[muonIndices[b]].p();
                            double m2 = pSum.m2Calc();
                            if (m2 <= 0.0) continue;
                            massHist.fill(std::sqrt(m2));
                            ++dimuonPairs;
                        }
                    }
            """,
            finalize: "",
            summaryLines: """
                summary << "dimuon_pairs=" << dimuonPairs << std::endl;
            """,
            extraOutput: """
                // Write hist_primary.txt
                std::ofstream histFile("hist_primary.txt");
                massHist.table(histFile, false, false);
                histFile.close();
            """
        )
    }

    // MARK: pid_yields

    private static func pidYieldsCode() -> FamilyCode {
        FamilyCode(
            declarations: """
                std::map<int, long long> pidCounts;
                pidCounts[211] = 0;
                pidCounts[-211] = 0;
                pidCounts[321] = 0;
                pidCounts[-321] = 0;
                pidCounts[2212] = 0;
            """,
            eventLoop: """
                    for (int i = 0; i < pythia.event.size(); ++i) {
                        if (pythia.event[i].isFinal()) {
                            int id = pythia.event[i].id();
                            if (pidCounts.find(id) != pidCounts.end())
                                pidCounts[id]++;
                        }
                    }
            """,
            finalize: "",
            summaryLines: """
                summary << "pid_211=" << pidCounts[211] << std::endl;
                summary << "pid_-211=" << pidCounts[-211] << std::endl;
                summary << "pid_321=" << pidCounts[321] << std::endl;
                summary << "pid_-321=" << pidCounts[-321] << std::endl;
                summary << "pid_2212=" << pidCounts[2212] << std::endl;
            """,
            extraOutput: """
                // Write pid_counts.txt (CSV)
                std::ofstream pidFile("pid_counts.txt");
                pidFile << "pid,count" << std::endl;
                for (auto& kv : pidCounts) {
                    pidFile << kv.first << "," << kv.second << std::endl;
                }
                pidFile.close();
            """
        )
    }

    // MARK: event_scalars

    private static func eventScalarsCode() -> FamilyCode {
        FamilyCode(
            declarations: """
                double totalVisibleEnergy = 0.0;
                double totalHT = 0.0;
            """,
            eventLoop: """
                    double eventVis = 0.0;
                    double eventHT = 0.0;
                    for (int i = 0; i < pythia.event.size(); ++i) {
                        if (pythia.event[i].isFinal() && pythia.event[i].isVisible()) {
                            eventVis += pythia.event[i].e();
                            eventHT += pythia.event[i].pT();
                        }
                    }
                    totalVisibleEnergy += eventVis;
                    totalHT += eventHT;
            """,
            finalize: "",
            summaryLines: """
                summary << "mean_visible_energy=" << (generatedEvents > 0 ? totalVisibleEnergy / generatedEvents : 0) << std::endl;
                summary << "mean_ht=" << (generatedEvents > 0 ? totalHT / generatedEvents : 0) << std::endl;
            """,
            extraOutput: """
                // Write event_scalars.txt
                std::ofstream scalarsFile("event_scalars.txt");
                scalarsFile << "mean_visible_energy=" << (generatedEvents > 0 ? totalVisibleEnergy / generatedEvents : 0) << std::endl;
                scalarsFile << "mean_ht=" << (generatedEvents > 0 ? totalHT / generatedEvents : 0) << std::endl;
                scalarsFile.close();
            """
        )
    }
}
