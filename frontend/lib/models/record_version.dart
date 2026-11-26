/// Confirmed server revision plus incarnation and timestamp identity.
/// Timestamp tokens retain nanoseconds without importing a database SDK here.
class RecordVersion {
  const RecordVersion(this.revision, this.createdAt, this.updatedAt);
  final int revision;
  final String createdAt;
  final String updatedAt;

  @override
  bool operator ==(Object other) =>
      other is RecordVersion &&
      revision == other.revision &&
      createdAt == other.createdAt &&
      updatedAt == other.updatedAt;
  @override
  int get hashCode => Object.hash(revision, createdAt, updatedAt);
}

enum ConflictReason { changed, deleted, unconfirmed, exhausted }

class RecordConflict implements Exception {
  const RecordConflict(this.reason);
  final ConflictReason reason;
  @override
  String toString() => switch (reason) {
    ConflictReason.changed => 'Data sudah berubah di perangkat lain. Draft tetap tersedia; muat data terbaru sebelum mencoba lagi.',
    ConflictReason.deleted => 'Data sudah dihapus. Draft tetap tersedia dan tidak disimpan ulang otomatis.',
    ConflictReason.unconfirmed => 'Versi data belum dikonfirmasi server. Tunggu koneksi dan muat ulang sebelum mengubah data.',
    ConflictReason.exhausted => 'Batas versi dokumen tercapai. Draft tetap tersedia; hubungi pengelola data.',
  };
}
