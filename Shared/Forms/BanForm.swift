import SwiftUI

struct BanForm: View {
    @State var divisionId: Int
    @State var penaltyLevel = 1
    
    var body: some View {
        FormPrimitive(title: "Ban User",
                      allowSubmit: true,
                      needConfirmation: true) {
            Picker(selection: $divisionId, label: Label("Banned Division", systemImage: "rectangle.3.group")) {
                ForEach(TreeholeDataModel.shared.divisions) { division in
                    Text(division.name)
                        .tag(division.id)
                }
            }
            
            Stepper(value: $penaltyLevel, in: 1...3) {
                Label("Penalty Level: \(penaltyLevel)", systemImage: "nosign")
            }
        } action: {
            // TODO: submit ban to server.
        }
    }
}

struct BanForm_Previews: PreviewProvider {
    static var previews: some View {
        BanForm(divisionId: 1)
    }
}
