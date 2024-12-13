///
///Casts a `List<dynamic>` to a list of lists of `T` values. The original lists typically comes from reading a JSON file.
///
List<List<T>> castMatrix<T>(List<dynamic> matrix) => matrix.map((row) => row.cast<T>()).toList().cast<List<T>>();