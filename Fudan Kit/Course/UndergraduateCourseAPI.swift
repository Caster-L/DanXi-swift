import Foundation
import SwiftyJSON
import Utils

/// API collection for academic and courses service.
/// These API are only available to undergraduate students.
public enum UndergraduateCourseAPI {
    
    // MARK: Login
    
    static let loginURL = URL(string: "https://fdjwgl.fudan.edu.cn/student/sso/login")!
    
    // MARK: - Courses
    
    /// Get all semesters from server
    ///
    /// - Returns:
    ///      A list of semesters and the current semester ID
    public static func getSemesters() async throws -> ([Semester], Int) {
        let url = URL(string: "https://fdjwgl.fudan.edu.cn/student/for-std/course-table")!
        let data = try await Authenticator.shared.authenticate(url, loginURL: loginURL)

        guard let html = String(data: data, encoding: .utf8) else { throw LocatableError() }

        let startDateMap = extractSemesterStartDates(from: html)

        let elements = try decodeHTMLElementList(data, selector: "option[value]")

        let semesters: [Semester] = elements
            .compactMap { element -> (id: Int, text: String)? in
                guard let value = try? element.attr("value"),
                      let id = Int(value),
                      let text = try? element.text() else {
                    return nil
                }

                return (id, text)
            }
            .reduce(into: [Int: String]()) { acc, pair in
                acc[pair.id] = acc[pair.id] ?? pair.text
            }
            .compactMap { id, text in
                guard let yearStr = text.firstMatch(of: #/(\d{4})-\d{4}/#)?.1,
                        let year    = Int(yearStr)
                else { return nil }

                let type: Semester.SemesterType =
                    if text.contains("1学期")      { .first  }
                    else if text.contains("2学期") { .second }
                    else if text.contains("暑")    { .summer }
                    else if text.contains("寒")    { .winter }
                    else                          { .first }

                return Semester(year: year,
                                type: type,
                                semesterId: id,
                                startDate: startDateMap[id],
                                weekCount: 18)
            }
            .sorted { ($0.year, $0.type.rawValue) > ($1.year, $1.type.rawValue) }

        let semesterIdPattern = #/'id':\s*"?(?<semester>\d{3,})"?/#
        guard let semesterStr = html.firstMatch(of: semesterIdPattern)?.semester,
              let semesterId  = Int(semesterStr) else {
            throw LocatableError()
        }

        return (semesters, semesterId)
    }
    
    /// Extract semester start dates from HTML page
    /// - Parameter html: HTML string containing JavaScript with semester data
    /// - Returns: Dictionary mapping semester ID to start date
    private static func extractSemesterStartDates(from html: String) -> [Int: Date] {
        let pattern = #/var\s+semesters\s*=\s*JSON\.parse\s*\(\s*'([\s\S]*?)'\s*\)/#

        guard let match = html.firstMatch(of: pattern) else {
            return [:]
        }

        let jsonString = String(match.1)

        func parseJSONData(_ data: Data) -> [Int: Date] {
            do {
                let decoder = JSONDecoder()
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                decoder.dateDecodingStrategy = .formatted(dateFormatter)

                let semesters = try decoder.decode([SemesterData].self, from: data)
                var dateMap: [Int: Date] = [:]
                for semester in semesters {
                    if let id = semester.id, let startDate = semester.startDate {
                        // fdjwgl returns the Sunday before the first teaching week; adjust +1 day.
                        dateMap[id] = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
                    }
                }
                return dateMap
            } catch {
                print("Error parsing semester JSON: \(error)")
                return [:]
            }
        }

        if let data = jsonString.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return parseJSONData(data)
        }
        var unescapedString = jsonString

        unescapedString = unescapedString.replacingOccurrences(of: #"\\\""#, with: #"\""#)
        unescapedString = unescapedString.replacingOccurrences(of: #"\\n"#, with: "\n")
        unescapedString = unescapedString.replacingOccurrences(of: #"\\r"#, with: "\r")
        unescapedString = unescapedString.replacingOccurrences(of: #"\\t"#, with: "\t")

        unescapedString = unescapedString.replacingOccurrences(of: #"\""#, with: #"""#)
        unescapedString = unescapedString.replacingOccurrences(of: #"\\"#, with: #""#)
        unescapedString = unescapedString.replacingOccurrences(of: #"\/"#, with: #"/"#)

        if let data = unescapedString.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return parseJSONData(data)
        }

        return [:]
    }

    private struct SemesterData: Decodable {
        let id: Int?
        let startDate: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case startDate
        }
    }


    /// Get course table for undergraduate
    /// - Parameters:
    ///   - semesterId: semester ID
    /// - Returns: A list of ``Course``, representing student course table
    ///

    private struct CourseBuilder: Codable {
        let lessonCode, courseName: String
        let room: String?
        let teachers: [String]
        let startUnit, endUnit, weekday: Int
        let weekIndexes: [Int]
        
        func build() -> Course {
            Course(id: UUID(),
                   name: courseName,
                   code: lessonCode,
                   teacher: teachers.first ?? "",
                   location: room ?? "",
                   weekday: weekday - 1,
                   start: startUnit - 1,
                   end: endUnit - 1,
                   onWeeks: weekIndexes)
        }
    }

    public static func getCourses(semesterId: Int) async throws -> [Course] {
        let url = URL(string: "https://fdjwgl.fudan.edu.cn/student/for-std/course-table/semester/\(semesterId)/print-data")!
        let data = try await Authenticator.shared.authenticate(url, loginURL: loginURL)
        let json = try JSON(data: data)
        let coursesData = try json["studentTableVms"][0]["activities"].rawData()
        
        let courseBuilders = try JSONDecoder().decode([CourseBuilder].self, from: coursesData)
        
        return courseBuilders.map { $0.build() }
    }

    /// Merge simultaneous rooms and teachers without changing the source records.
    static func mergeCourses(_ courses: [Course]) -> [Course] {
        struct Slot: Hashable {
            let code, name: String
            let weekday, start, end: Int
        }
        struct Details: Hashable {
            let teacher, location: String
        }

        func joined(_ values: [String]) -> String {
            Set(values.flatMap { $0.split(separator: ",") }
                .map { $0.trimmingCharacters(in: .whitespaces) })
                .filter { !$0.isEmpty }.sorted().joined(separator: ", ")
        }

        let slots = Dictionary(grouping: courses) {
            Slot(code: $0.code, name: $0.name, weekday: $0.weekday, start: $0.start, end: $0.end)
        }
        var result: [Course] = []
        for (slot, records) in slots {
            var weeksByDetails: [Details: [Int]] = [:]
            // Resolve each week's actual rooms before regrouping the weeks.
            for week in Set(records.flatMap(\.onWeeks)).sorted() {
                let active = records.filter { $0.openOn(week) }
                let details = Details(teacher: joined(active.map(\.teacher)),
                                      location: joined(active.map(\.location)))
                weeksByDetails[details, default: []].append(week)
            }

            for (details, weeks) in weeksByDetails {
                // Keep weekly/fortnightly runs separate across room changes or gaps.
                var index = 0
                while index < weeks.count {
                    var end = index + 1
                    if end < weeks.count {
                        let interval = weeks[end] - weeks[index]
                        if interval == 1 || interval == 2 {
                            end += 1
                            while end < weeks.count && weeks[end] - weeks[end - 1] == interval {
                                end += 1
                            }
                        }
                    }
                    result.append(Course(id: UUID(), name: slot.name, code: slot.code,
                                         teacher: details.teacher, location: details.location,
                                         weekday: slot.weekday, start: slot.start, end: slot.end,
                                         onWeeks: Array(weeks[index..<end])))
                    index = end
                }
            }
        }
        return result.sorted {
            if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.code != $1.code { return $0.code < $1.code }
            return $0.onWeeks.lexicographicallyPrecedes($1.onWeeks)
        }
    }

    // MARK: - Exam
    
    /// Get user's exam list
    ///
    /// ## API Detail
    ///
    /// This API uses the neo authentication to fetch exam information from the new endpoint.
    /// The new endpoint returns HTML with an exam table.
    ///
    /// - Returns: A list of ``Exam``, including both finished and upcoming exams
    ///
    /// Exam status:
    /// - Exams with class "finished hide" are completed exams
    /// - Exams with class "unfinished" are upcoming/pending exams
    ///
    /// ## Example HTML Response:
    /// ```html
    /// <tr data-finished="false" class="unfinished">
    ///     <td>
    ///         <div class="time">2026-01-04 08:30~10:30</div>
    ///         <div>
    ///             <span>邯郸校区</span>
    ///             <span>H邯郸校区第六教学楼</span>
    ///             <span>H6506</span>
    ///         </div>
    ///     </td>
    ///     <td>
    ///         <div>
    ///             <span>数字集成电路设计原理(H) </span>
    ///             <span>ICSE30021h.01 </span>
    ///             <span>（闭卷） </span>
    ///         </div>
    ///         <div>
    ///             <span class="tag-span type2">期末</span>
    ///         </div>
    ///     </td>
    ///     <td>请携带学生证或一卡通，待考试时核查。</td>
    ///     <td>未结束</td>
    /// </tr>
    /// <tr data-finished="true" class="finished hide">
    ///     <td>
    ///         <div class="time ">2025-11-11 13:00~15:00</div>
    ///         <div>
    ///             <span>邯郸校区</span>
    ///             <span>H邯郸校区第二教学楼</span>
    ///             <span>H2115</span>
    ///         </div>
    ///     </td>
    ///     <td>
    ///         <div>
    ///             <span>半导体器件原理(H) </span>
    ///             <span>ICSE30020h.01 </span>
    ///             <span>（半开卷） </span>
    ///         </div>
    ///         <div>
    ///             <span class="tag-span type1">期中</span>
    ///         </div>
    ///     </td>
    ///     <td>请携带学生证或一卡通，待考试时核查。</td>
    ///     <td>已结束</td>
    /// </tr>
    /// ```
    public static func getExams() async throws -> [Exam] {
        let studentId = try await getStudentId()
        let url = URL(string: "https://fdjwgl.fudan.edu.cn/student/for-std/exam-arrange/info/\(studentId)")!
        let data = try await Authenticator.shared.authenticate(url, loginURL: loginURL)

        var exams: [Exam] = []

        let elements = try decodeHTMLElementList(data, selector: "table.exam-table tbody tr")
        for element in elements {
            let classAttr = try? element.attr("class")
            if let classAttr = classAttr, classAttr.contains("tr-empty") {
                continue
            }
            guard let courseCell = try? element.select("td[data-label=\"课程信息\"]").first(),
                  let spans = try? courseCell.select("span").array() else {
                continue
            }

            var courseId = ""
            var course = ""
            var type = ""
            var method = "无"
            var date = ""
            var time = ""
            var location = ""
            var note = ""

            let dataFinishedAttr = try? element.attr("data-finished")
            let isFinished = dataFinishedAttr == "true" || (classAttr?.split(separator: " ").contains { $0 == "finished" } ?? false)

            var courseTexts: [String] = []
            for span in spans {
                let spanClass = (try? span.attr("class")) ?? ""
                let text = ((try? span.text(trimAndNormaliseWhitespace: true)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }

                if spanClass.split(separator: " ").contains(where: { $0 == "tag-span" }) {
                    type = text
                } else if (text.hasPrefix("（") && text.hasSuffix("）")) || (text.hasPrefix("(") && text.hasSuffix(")")) {
                    method = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if text.range(of: #"^[A-Za-z]+\d+[A-Za-z]*(\.\d+)?$"#, options: .regularExpression) != nil {
                    courseId = text
                } else {
                    courseTexts.append(text)
                }
            }
            course = courseTexts.joined(separator: " ")

            if let timeDiv = try? element.select("td[data-label=\"考试信息\"] .time").first(),
               let timeText = try? timeDiv.text(trimAndNormaliseWhitespace: true) {
                let trimmedTime = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let dateMatch = trimmedTime.firstMatch(of: /(\d{4}-\d{2}-\d{2})/) {
                    date = String(dateMatch.1)
                    time = String(trimmedTime[dateMatch.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if let locationCell = try? element.select("td[data-label=\"场地信息\"]").first(),
               let spanArray = try? locationCell.select("span").array(),
               spanArray.count > 2 {
                let parsedLocation = ((try? spanArray[2].text(trimAndNormaliseWhitespace: true)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !parsedLocation.isEmpty && parsedLocation != "--" {
                    location = parsedLocation
                }
            }

            if let noteCell = try? element.select("td[data-label=\"备注\"]").first() {
                note = ((try? noteCell.text(trimAndNormaliseWhitespace: true)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let exam = Exam(id: UUID(), courseId: courseId, course: course, type: type, method: method, date: date, time: time, location: location, note: note, isFinished: isFinished)
            exams.append(exam)
        }

        return exams
    }
    
    // MARK: - Score and GPA

    /// Get semesters from the grade sheet, including those without timetable entries.
    public static func getScoreSemesters() async throws -> ([Semester], Semester?) {
        let studentId = try await getStudentId()
        let url = URL(string: "https://fdjwgl.fudan.edu.cn/student/for-std/grade/sheet/semester-index/\(studentId)")!
        let data = try await Authenticator.shared.authenticate(url, loginURL: loginURL)
        let elements = try decodeHTMLElementList(data, selector: "select#semester option[value]")

        let semesters: [Semester] = try elements.compactMap { element in
            let text = try element.text()
            guard let id = Int(try element.attr("value")),
                  let yearStr = text.firstMatch(of: #/(\d{4})-\d{4}/#)?.1,
                  let year = Int(yearStr) else { return nil }
            let type: Semester.SemesterType =
                if text.contains("1学期") { .first }
                else if text.contains("2学期") { .second }
                else if text.contains("暑") { .summer }
                else if text.contains("寒") { .winter }
                else { .first }

            return Semester(year: year, type: type, semesterId: id, startDate: nil, weekCount: 18)
        }.sorted(by: >)

        return (semesters, semesters.first)
    }

    /// Get  student ID from course table API
    private static func getStudentId() async throws -> String {
        let (_, semesterId) = try await getSemesters()

        let url = URL(string: "https://fdjwgl.fudan.edu.cn/student/for-std/course-table/semester/\(semesterId)/print-data")!
        let data = try await Authenticator.shared.authenticate(url, loginURL: loginURL)
        let json = try JSON(data: data)

        guard let studentId = json["studentTableVms"][0]["id"].int else {
            throw LocatableError()
        }

        return String(studentId)
    }

    /// Get the student course score on a given semeser
    /// - Parameter semester: Semester ID
    /// - Returns: A list of ``Score``
    public static func getScore(semester: Int) async throws -> [Score] {
        let studentId = try await getStudentId()

        let url = URL(string: "https://fdjwgl.fudan.edu.cn/student/for-std/grade/sheet/info/\(studentId)?semester=\(semester)")!
        let data = try await Authenticator.shared.authenticate(url, loginURL: loginURL)

        let json = try JSON(data: data)
        let semesterKey = String(semester)
        guard let gradesArray = json["semesterId2studentGrades"][semesterKey].array else {
            return []
        }

        var scores: [Score] = []
        for gradeJson in gradesArray {
            guard let gradeData = try? gradeJson.rawData() else { continue }
            let decoder = JSONDecoder()
            if let scoreResponse = try? decoder.decode(ScoreResponse.self, from: gradeData) {
                var courseTypeText = scoreResponse.courseModuleTypeName ?? scoreResponse.courseType ?? ""
                if let commaIndex = courseTypeText.firstIndex(of: ",") {
                    courseTypeText = String(courseTypeText[..<commaIndex])
                }

                let score = Score(
                    id: UUID(),
                    courseId: [scoreResponse.lessonCode, scoreResponse.courseCode].compactMap { $0 }.first { !$0.isEmpty },
                    courseName: scoreResponse.courseName,
                    courseType: courseTypeText,
                    courseCredit: nil,
                    grade: scoreResponse.gaGrade,
                    gradePoint: scoreResponse.gp != nil ? String(format: "%.3f", scoreResponse.gp!) : ""
                )
                scores.append(score)
            }
        }

        return scores
    }

    private struct ScoreResponse: Decodable {
        let lessonCode: String?
        let courseCode: String?
        let courseName: String
        let courseType: String?
        let courseModuleTypeName: String?
        let gaGrade: String
        let gp: Double?
    }
    
    /// Get the rank list, aka GPA ranking table (department-wide ranking)
    public static func getRanks() async throws -> [Rank] {
        let studentId = try await getStudentId()
        
        // Get departmentAssoc and grade from search-index page
        let indexURL = URL(string: "https://fdjwgl.fudan.edu.cn/student/for-std/grade/my-gpa/search-index/\(studentId)")!
        let indexData = try await Authenticator.shared.authenticate(indexURL, loginURL: loginURL)
        
        guard let html = String(data: indexData, encoding: .utf8),
              let gradeMatch = html.firstMatch(of: /name="grade"\s+value="(\d+)"/),
              let deptMatch = html.firstMatch(of: /name="departmentAssoc"\s+value="(\d+)"/) else {
            throw LocatableError()
        }
        
        // get department GPA ranks
        let searchURL = URL(string: "https://fdjwgl.fudan.edu.cn/student/for-std/grade/my-gpa/search?studentAssoc=\(studentId)&grade=\(gradeMatch.1)&departmentAssoc=\(deptMatch.1)&majorAssoc=")!
        let searchData = try await Authenticator.shared.authenticate(searchURL, loginURL: loginURL)
        
        guard let ranksArray = try JSON(data: searchData)["data"].array else {
            return []
        }
        
        return ranksArray.compactMap { rankJson -> Rank? in
            guard let name = rankJson["name"].string,
                  let grade = rankJson["grade"].string,
                  let major = rankJson["major"].string,
                  let department = rankJson["department"].string,
                  let gpa = rankJson["gpa"].double,
                  let credit = rankJson["credit"].double,
                  let ranking = rankJson["ranking"].int else {
                return nil
            }
            return Rank(id: UUID(), name: name, grade: grade, major: major, department: department, gradePoint: gpa, credit: credit, rank: ranking)
        }
    }
}
