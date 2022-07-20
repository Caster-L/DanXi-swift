import Foundation
import SwiftUI

@MainActor
class THData: ObservableObject {
    var token = ""
    @Published var endReached = false
    @Published var loading = false
    @Published var holes: [OTHole] = []
    @Published var divisions: [OTDivision] = []
    @Published var currentDivision = OTDivision(id: 1, name: "树洞", description: "", pinned: [])
    
    init() {
        let defaults = UserDefaults(suiteName: "group.io.github.kavinzhao.fdutools") // TODO: move to keychain
        token = defaults?.string(forKey: "user_credential") ?? ""
    }
    
    init(divisions: [OTDivision], holes: [OTHole]) { // for preview purpose
        self.divisions = divisions
        self.holes = holes
        currentDivision = self.divisions[0]
    }
    
    var notInitiazed: Bool {
        !loading && divisions.isEmpty
    }
    
    
    func initialFetch() async {
        do {
            loading = true
            let fetchedDivisions = try await THloadDivisions(token: token)
            let fetchedHoles = try await THloadHoles(token: token, divisionId: fetchedDivisions[0].id)
            withAnimation {
                divisions = fetchedDivisions
                currentDivision = fetchedDivisions[0]
                holes = fetchedHoles
                loading = false
            }
        } catch {
            print("load division fail")
        }
    }
    
    func fetchMoreHoles() async {
        loading = true
        do {
            let newHoles = try await THloadHoles(token: token, divisionId: currentDivision.id)
            if newHoles.isEmpty {
                endReached = true
            } else {
                withAnimation {
                    holes.append(contentsOf: newHoles)
                }
            }
        } catch {
            endReached = true
        }
        loading = false
    }
    
    func changeDivision(division: OTDivision) async {
        withAnimation {
            currentDivision = division
            endReached = false
            holes = []
        }
        do {
            let fetchedHoles = try await THloadHoles(token: token, divisionId: division.id)
            withAnimation {
                holes = fetchedHoles
            }
        } catch {
            print("change division fail")
        }
    }
}
