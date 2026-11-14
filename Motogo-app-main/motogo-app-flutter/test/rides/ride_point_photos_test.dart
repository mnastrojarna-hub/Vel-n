// Fotky zastávky: po částečném nahrání se nahrané soubory NEnahrají znovu
// (dřív druhé „Uložit“ nahrálo celou dávku a fotky se zdvojily přes limit 8).
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/routes/ride_point_sheet.dart';

void main() {
  test('partial upload: two URLs added, the failed file stays pending', () {
    final m = mergeUploadedPhotos(['old'], ['f1', 'f2', 'f3'], ['url1', null, 'url3']);
    expect(m.photos, ['old', 'url1', 'url3']);
    expect(m.pending, ['f2']);
    expect(m.failed, 1);
  });

  test('second round uploads only the pending file: three distinct URLs, nothing pending', () {
    final first = mergeUploadedPhotos(<String>[], ['f1', 'f2', 'f3'], ['url1', null, 'url3']);
    final second = mergeUploadedPhotos(first.photos, first.pending, ['url2']);
    expect(second.photos, ['url1', 'url3', 'url2']);
    expect(second.photos.toSet(), hasLength(3));
    expect(second.pending, isEmpty);
    expect(second.failed, 0);
  });

  test('a URL already present is not added twice', () {
    final m = mergeUploadedPhotos(['url1'], ['f1'], ['url1']);
    expect(m.photos, ['url1']);
  });

  test('never more than 8 photos', () {
    final have = [for (var i = 0; i < 6; i++) 'u$i'];
    final m = mergeUploadedPhotos(have, ['a', 'b', 'c', 'd'], ['x1', 'x2', 'x3', 'x4']);
    expect(m.photos, hasLength(8));
    expect(m.photos.take(6), have);
    expect(mergeUploadedPhotos(have, ['a'], [null]).photos, hasLength(6));
  });

  test('results shorter than the batch count as failed', () {
    final m = mergeUploadedPhotos(<String>[], ['f1', 'f2'], ['url1']);
    expect(m.pending, ['f2']);
    expect(m.failed, 1);
  });
}
