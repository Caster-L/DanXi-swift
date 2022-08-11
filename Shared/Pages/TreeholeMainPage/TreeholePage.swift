import SwiftUI
import Foundation

struct TreeholePage: View {
    @ObservedObject var model = treeholeDataModel
    @StateObject var viewModel = TreeholeViewMode()

    @State var searchText = ""
    @State var showEditPage = false
    @State var searchSubmitted = false
    
    var body: some View {
        List {
            if searchText.isEmpty {
                pinnedSection
                mainSection
            } else {
                searchSection
                    .background(
                        NavigationLink(destination: SearchTextPage(keyword: searchText), isActive: $searchSubmitted) {
                            EmptyView()
                        })
            }
        }
        .task {
            await viewModel.initialLoad()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .onSubmit(of: .search) {
            searchSubmitted = true
        }
        .listStyle(.grouped)
        .navigationTitle(viewModel.currentDivision.name)
        .alert(viewModel.errorInfo.title, isPresented: $viewModel.errorPresenting) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorInfo.description)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                toolBar
            }
        }
    }
    
    private var filteredTags: [THTag] {
        return model.tags.filter { $0.name.contains(searchText) }
    }
    
    @ViewBuilder
    private var searchSection: some View {
        Section("search_text") {
            NavigationLink(destination: SearchTextPage(keyword: searchText)) {
                Label(searchText, systemImage: "magnifyingglass")
            }
        }
        // navigate to hole by ID, don't assume hole id length
        if searchText ~= #"^#[0-9]+$"#, let holeId = Int(searchText.dropFirst(1)) {
            Section("jump_to_hole") {
                NavigationLink(destination: HoleDetailPage(holeId: holeId)) {
                    Label(searchText, systemImage: "arrow.right.square")
                }
            }
        }
        
        // navigate to floor by ID, don't assume floor id length
        if searchText ~= #"^##[0-9]+$"#, let floorId = Int(searchText.dropFirst(2)) {
            Section("jump_to_floor") {
                NavigationLink(destination: HoleDetailPage(targetFloorId: floorId)) {
                    Label(searchText, systemImage: "arrow.right.square")
                }
            }
        }
        
        if !filteredTags.isEmpty {
            Section("tags") {
                ForEach(filteredTags) { tag in
                    NavigationLink(destination: SearchTagPage(tagname: tag.name, divisionId: viewModel.currentDivisionId)) {
                        Label(tag.name, systemImage: "tag")
                    }
                }
            }
        }
    }
    
    private var pinnedSection: some View {
        Section {
            ForEach(viewModel.currentDivision.pinned) { hole in
                HoleView(hole: hole)
                    .background(NavigationLink("", destination: HoleDetailPage(hole: hole)).opacity(0))
            }
        } header: {
            VStack(alignment: .leading) {
                switchBar
                if !viewModel.currentDivision.pinned.isEmpty {
                    Label("pinned", systemImage: "pin.fill")
                }
            }
        }
        .textCase(nil)
    }
    
    private var mainSection: some View {
        Section {
            ForEach(viewModel.holes) { hole in
                HoleView(hole: hole)
                    .background(NavigationLink("", destination: HoleDetailPage(hole: hole)).opacity(0))
                    .task {
                        if hole == viewModel.holes.last {
                            await viewModel.loadMoreHoles()
                        }
                    }
            }
        } header: {
            Label("main_section", systemImage: "text.bubble.fill")
        } footer: {
            spinner
        }
        .textCase(nil)
    }
    
    private var switchBar: some View {
        Picker("division_selector", selection: $viewModel.currentDivisionId) {
            ForEach(model.divisions) { division in
                Text(division.name)
                    .tag(division.id)
            }
        }
        .pickerStyle(.segmented)
        .offset(x: 0, y: -40)
        .onChange(of: viewModel.currentDivisionId) { newValue in
            Task {
                let newDivision = model.divisions[newValue - 1]
                await viewModel.changeDivision(division: newDivision)
            }
        }
    }
    
    private var toolBar: some View {
        Group {
            ToolbarMenu() // menu item can't perform navigation, this is a workaround
            
            Button(action: { showEditPage = true }) {
                Image(systemName: "square.and.pencil")
            }
            .sheet(isPresented: $showEditPage) {
                EditPage(divisionId: viewModel.currentDivisionId, showNewPostPage: $showEditPage)
            }
        }
    }
    
    private var spinner: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
    }
}

struct ToolbarMenu: View {
    @State private var isActive = false // menu navigation workaround
    @State private var navigationTarget: AnyView?
    
    var body: some View {
        Menu {
            Button {
                self.navigationTarget = AnyView(FavoritesPage())
                self.isActive = true
            } label: {
                Label("favorites", systemImage: "star")
            }
            
            Button {
                self.navigationTarget = AnyView(TagPage())
                self.isActive = true
            } label: {
                Label("tags", systemImage: "tag")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .background(
            NavigationLink(destination: navigationTarget, isActive: $isActive) {
                EmptyView()
            })
    }
    
}

struct TreeholePage_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            TreeholePage()
        }
    }
}
