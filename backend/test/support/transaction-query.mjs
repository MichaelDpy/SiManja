import {
  collection, query, where, orderBy, documentId, startAfter, limit, Timestamp,
} from 'firebase/firestore';

// SDK test/benchmark mirror of R-HISTORY v1. The production Dart builder is
// separately checked by the recording SDK tests and native probe.
export function historyQuery(db, uid, { from, until, pageSize = 50 } = {}, after) {
  const filters = [where('dateVersion', '==', 2)];
  if (from) filters.push(where('date', '>=', Timestamp.fromDate(new Date(from))));
  if (until) filters.push(where('date', '<', Timestamp.fromDate(new Date(until))));
  filters.push(orderBy('date', 'desc'), orderBy(documentId(), 'desc'));
  if (after) filters.push(startAfter(after.date, after.id));
  filters.push(limit(pageSize + 1));
  return query(collection(db, `users/${uid}/transactions`), ...filters);
}

export function pageOf(snapshot, pageSize) {
  const rows = snapshot.docs.slice(0, pageSize);
  return {
    rows,
    after: snapshot.size > pageSize
      ? { date: rows.at(-1).data().date, id: rows.at(-1).id } : null,
  };
}
