import Charts
import FudanKit
import SwiftUI

struct FDElectricityPage: View {
    var body: some View {
        AsyncContentView(animation: .default) {
            async let usage = ElectricityStore.shared.getCachedElectricityUsage()
            async let dateValues = MyStore.shared.getCachedElectricityLogs().map { FDDateValueChartData(date: $0.date, value: $0.usage) }
            
            let (usageLoaded, dateValuesLoaded) = try await (usage, dateValues)
            
            let filteredDateValues = Array(FDDateValueChartData.formattedData(dateValuesLoaded)[0 ..< min(7, dateValuesLoaded.count)])
                        
            return (usageLoaded, filteredDateValues)
        } content: { (info: ElectricityUsage, transactions: [FDDateValueChartData]) in
            List {
                LabeledContent {
                    Text(info.campus)
                } label: {
                    Text("Campus")
                }
                
                LabeledContent {
                    Text(info.building + info.room)
                } label: {
                    Text("Dorm")
                }
                
                LabeledContent {
                    Text("\(String(info.electricityAvailable)) kWh")
                } label: {
                    Text("Electricity Available")
                }
                
                LabeledContent {
                    Text("\(String(info.electricityUsed)) kWh")
                } label: {
                    Text("Electricity Used")
                }
                
                if #available(iOS 17, *) {
                    FDElectricityPageChart(data: transactions)
                }
            }
            .navigationTitle("Dorm Electricity")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

@available(iOS 17.0, *)
private struct FDElectricityPageChart: View {
    let data: [FDDateValueChartData]
    @State private var chartSelection: Date?
    
    private var areaBackground: Gradient {
        return Gradient(colors: [.green.opacity(0.5), .clear])
    }
    
    var body: some View {
        Section("Electricity Usage History") {
            Chart {
                ForEach(data) { d in
                    LineMark(
                        x: .value("Date", d.date, unit: .day),
                        y: .value("kWh", d.value)
                    )
                    
                    AreaMark(
                        x: .value("Date", d.date, unit: .day),
                        y: .value("", d.value)
                    )
                    .foregroundStyle(areaBackground)
                }
                
                if let selectedDate = chartSelection,
                   let selectedData = data.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) })
                {
                    RuleMark(x: .value("Date", selectedDate, unit: .day))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.secondary)
                        .annotation(
                            position: .top, spacing: 0,
                            overflowResolution: .init(
                                x: .fit(to: .chart),
                                y: .disabled
                            )
                        ) {
                            VStack {
                                Text("\(selectedData.date, format: .dateTime.day().month())")
                                Text("\(String(format: "%.2f", selectedData.value)) kWh")
                            }
                            .foregroundStyle(.green)
                            .font(.system(.caption, design: .rounded))
                            .padding(.bottom, 4)
                            .padding(.trailing, 12)
                        }
                    PointMark(
                        x: .value("Date", selectedData.date, unit: .day),
                        y: .value("kWh", selectedData.value)
                    )
                    .symbolSize(30)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                }
            }
            .chartYAxisLabel(String(localized: "kWh"))
            .frame(height: 200)
            .chartXSelection(value: $chartSelection)
            .foregroundColor(.green)
        }
        .padding(.top, 8) // Leave space for annotation
    }
}
