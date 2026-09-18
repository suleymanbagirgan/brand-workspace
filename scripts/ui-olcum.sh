#!/bin/zsh
# 0.2.1 arayüz ölçümü (docs/surum-0.2.1.md §8): Sources/MarkaApp üzerinde metin tabanlı (perl) sayımlar.
# Kullanım: scripts/ui-olcum.sh [kaynak klasörü]   (varsayılan: Sources/MarkaApp)
#
# Yöntem — sayımlar kod metninden yapılır; ekranda aynı anda görünen düğme sayısı değildir. Yorumlar (`//`) sayılmaz.
#   Button          : `Button(` ve `Button {` geçişleri (ButtonStyle, SettingsLink, RefButton gibi ad parçaları sayılmaz).
#                     §8'deki sayı TOPLAMDIR; menü öğeleri de düğmedir ve toplamın içindedir. Ayrıca kırılım verilir:
#                       ekranda     : hiçbir menü/diyalog bloğunun içinde olmayan geçiş
#                       menü        : `TextMenu(…) { }`, `Menu { }`, `.contextMenu { }` içindeki geçiş (sağ tık/açılır menü öğesi;
#                                     blokta adıyla anılan `var x: some View` gövdesi dahil)
#                       menü çubuğu : `CommandMenu`/`CommandGroup` içindeki geçiş (uygulama menüsü, kısayollar)
#                       diyalog     : `.confirmationDialog`/`.alert` içindeki geçiş
#                     Düğme içeren ve ≥ 2 yerden çağrılan bileşen/yardımcılar ayrıca listelenir: tek `Button` geçişi
#                     birden çok ekran düğmesi üretebilir; sayı bununla süslenmesin diye çağrı sayıları açıkça yazılır
#                     (ekran çizimi aracı SnapshotRunner'daki çağrılar hariç).
#   Düğme dışı eylem: işlevsel `.onTapGesture` (seçim, kapatma) ve `TextMenu(` tetikleyicileri ayrı kalemde (U9); §8 hedefi
#                     `Button` geçişidir, bunlar düğmeye taşınmadan eylem gizlenmesin diye ayrıca yazılır.
#   Sayfa türü      : `.sheet(`/`.popover(` kapanışında (switch dahil) oluşturulan, kaynakta tanımlı her `View` türü.
#                     Kapanışta tür bulunamazsa uyarı yazılır. Onay diyaloğu, uyarı ve sistem panelleri ayrı kalemde.
#   Yazı stili      : farklı `.font(…)` ifadesi; `Design.Font.*` dışındakiler dosya:satır ile listelenir. `.fontWeight(`
#                     ve `.monospacedDigit()` stil çeşitlemesidir; ayrı sayılır.
#   SF Symbol       : `systemName:`/`systemImage:`/`symbol:` sonrası ve `var symbol` gövdelerindeki farklı simge dizgesi
#   Boşluk          : `spacing:` ve `.padding(` içindeki farklı sayı değerleri (Design.* belirteçleri sayı değildir)
#   Metin           : benzersiz `L("…")`/`LF("…")` anahtarı
set -euo pipefail
cd "$(dirname "$0")/.."
DIR="${1:-Sources/MarkaApp}"
FILES=("$DIR"/**/*.swift(N))
(( ${#FILES} )) || { echo "Swift dosyası yok: $DIR" >&2; exit 1; }

perl - "$DIR" "${FILES[@]}" <<'PERL'
use strict; use warnings; use utf8;
binmode STDOUT, ':encoding(UTF-8)';
my ($dir, @files) = @ARGV;

# Yorumları at (dizge içindeki "//" korunur). Satır sayısı değişmez.
sub strip_comments {
    my ($text) = @_;
    my @out;
    for my $line (split /\n/, $text, -1) {
        my ($in, $res) = (0, '');
        my @c = split //, $line;
        for (my $i = 0; $i < @c; $i++) {
            if ($in) { $res .= $c[$i]; if ($c[$i] eq '\\') { $res .= $c[++$i] // ''; } elsif ($c[$i] eq '"') { $in = 0 } next }
            if ($c[$i] eq '"') { $in = 1; $res .= $c[$i]; next }
            last if $c[$i] eq '/' && ($c[$i + 1] // '') eq '/';
            $res .= $c[$i];
        }
        push @out, $res;
    }
    join "\n", @out;
}

# $pos konumundaki açılış ayracının ( '(' ya da '{' ) eşinin konumu; dizgeler atlanır.
sub match_close {
    my ($t, $pos) = @_;
    my $open = substr($t, $pos, 1);
    my $close = $open eq '(' ? ')' : '}';
    my ($depth, $in) = (0, 0);
    for (my $i = $pos; $i < length $t; $i++) {
        my $ch = substr($t, $i, 1);
        if ($in) { if ($ch eq '\\') { $i++ } elsif ($ch eq '"') { $in = 0 } next }
        if ($ch eq '"') { $in = 1; next }
        if ($ch eq $open) { $depth++ } elsif ($ch eq $close) { $depth--; return $i if $depth == 0 }
    }
    return length($t) - 1;
}

# Eşleşmenin (sonu '(' ya da '{') ardından gelen ilk kapanış bloğu: [başlangıç, bitiş].
sub trailing_block {
    my ($t, $end) = @_;   # $end: eşleşmenin son karakterinin konumu
    my $p = $end;
    if (substr($t, $p, 1) eq '(') { $p = match_close($t, $p) + 1 }
    elsif (substr($t, $p, 1) eq '{') { return [$p, match_close($t, $p)] }
    while ($p < length $t && substr($t, $p, 1) =~ /\s/) { $p++ }
    return undef unless substr($t, $p, 1) eq '{';
    return [$p, match_close($t, $p)];
}

sub line_of { my ($t, $pos) = @_; 1 + (() = substr($t, 0, $pos) =~ /\n/g) }

my (%code, %raw);
for my $f (@files) {
    local $/; open my $h, '<:encoding(UTF-8)', $f or die "$f: $!"; $raw{$f} = <$h>; close $h;
    $code{$f} = strip_comments($raw{$f});
}
my $all = join "\n", map { $code{$_} } @files;
sub short { my $f = shift; $f =~ s{^.*/}{}; $f }

# --- Tanımlı View türleri
my %views;
while ($all =~ /\bstruct\s+(\w+)(?:<[^>{]*>)?\s*:\s*[^{]*?\bView\b/g) { $views{$1} = 1 }

# --- Düğmeler ve kırılım
my %region_kind = (
    'TextMenu' => 'menü', 'Menu' => 'menü', 'contextMenu' => 'menü',
    'CommandMenu' => 'menü çubuğu', 'CommandGroup' => 'menü çubuğu',
    'confirmationDialog' => 'diyalog', 'alert' => 'diyalog',
);
my (%btn, %btn_file, $btn_total);
for my $f (@files) {
    my $t = $code{$f};
    my @regions;
    while ($t =~ /(?:\b(TextMenu|Menu|CommandMenu|CommandGroup)\s*[({]|\.(contextMenu|confirmationDialog|alert)\s*[({])/g) {
        my $name = $1 // $2;
        my $b = trailing_block($t, pos($t) - 1) or next;
        push @regions, [$b->[0], $b->[1], $region_kind{$name}];
    }
    # Menü bloğunda adıyla anılan `var x: some View { … }` gövdesi de o menünün öğeleridir (ör. `TextMenu { menuItems }`).
    for my $r (@regions) {
        my $inner = substr($t, $r->[0], $r->[1] - $r->[0] + 1);
        while ($t =~ /\bvar\s+(\w+)\s*:\s*some\s+View\s*\{/g) {
            my ($name, $open) = ($1, pos($t) - 1);
            next unless $inner =~ /\b\Q$name\E\b/;
            push @regions, [$open, match_close($t, $open), $r->[2]];
        }
    }
    while ($t =~ /\bButton\s*[({]/g) {
        my $p = pos($t) - 1;
        my $kind = 'ekranda';
        for my $r (@regions) { if ($p > $r->[0] && $p < $r->[1]) { $kind = $r->[2]; last } }
        $btn{$kind}++; $btn_file{short($f)}++; $btn_total++;
    }
}

# --- Düğme içeren, ≥ 2 yerden çağrılan bileşen/yardımcılar
my %wrapper_calls;
for my $f (@files) {
    my $t = $code{$f};
    while ($t =~ /\b(struct|func)\s+(\w+)\b/g) {
        my ($kw, $name) = ($1, $2);
        my $start = pos($t);
        next if $kw eq 'struct' && !$views{$name};
        my $brace = index($t, '{', $start); next if $brace < 0;
        if ($kw eq 'func') { my $sig = substr($t, $start, $brace - $start); next unless $sig =~ /->\s*some\s+View/ }
        my $end = match_close($t, $brace);
        my $body = substr($t, $brace, $end - $brace + 1);
        next unless $body =~ /\bButton\s*[({]/;
        # Yapı her dosyadan, yardımcı işlev yalnız kendi dosyasından çağrılır; ekran çizimi aracı (SnapshotRunner) sayılmaz.
        my $scope = $kw eq 'struct' ? join("\n", map { $code{$_} } grep { !/SnapshotRunner/ } @files) : $t;
        my $calls = () = $scope =~ /(?<!func )(?<!struct )\b\Q$name\E\s*[({]/g;
        $wrapper_calls{$name} = $calls if $calls >= 2;
    }
}

# --- Düğme olmayan eylem tetikleyicileri (U9): `Button` sayımına girmeyen ama tıklanınca iş yapan yerler.
#   onTapGesture : satır seçimi, panel kapatma, kutu etiketine tıklama gibi işlevsel dokunma eylemleri (dosya:satır)
#   TextMenu     : açılır metin menüsünün tetikleyicisi (menü öğeleri ayrıca "menü öğesi" olarak sayılır)
my (@taps, @menus);
for my $f (@files) {
    my $t = $code{$f};
    while ($t =~ /\.onTapGesture\b/g) { push @taps, short($f) . ':' . line_of($t, pos($t)) }
    while ($t =~ /(?<!struct )\bTextMenu\s*\(/g) { push @menus, short($f) . ':' . line_of($t, pos($t)) }
}

# --- Sayfa türleri (sheet/popover), diyaloglar, sistem panelleri
my (%sheet_types, @sheet_warn, $sheets);
for my $f (@files) {
    my $t = $code{$f};
    while ($t =~ /\.(sheet|popover)\s*\(/g) {
        $sheets++;
        my $b = trailing_block($t, pos($t) - 1);
        my $found = 0;
        if ($b) {
            my $body = substr($t, $b->[0], $b->[1] - $b->[0] + 1);
            while ($body =~ /\b([A-Z]\w*)\s*[({]/g) { if ($views{$1}) { $sheet_types{$1} = 1; $found = 1 } }
        }
        push @sheet_warn, short($f) . ':' . line_of($t, pos($t)) unless $found;
    }
}
my $dialogs = () = $all =~ /\.confirmationDialog\s*\(/g;
my $alerts = () = $all =~ /\.alert\s*\(/g;
my $panels = () = $all =~ /\.fileImporter\s*\(|\bNSOpenPanel\s*\(|\bNSSavePanel\s*\(/g;

# --- Yazı stili
my (%fonts, @font_other);
for my $f (@files) {
    my $t = $code{$f};
    while ($t =~ /\.font\(((?:[^()]++|\((?1)\))*)\)/g) {
        (my $x = $1) =~ s/\s+//g;
        $fonts{$x} = 1;
        push @font_other, short($f) . ':' . line_of($t, pos($t)) . "  .font($x)" unless $x =~ /^Design\.Font\./;
    }
}
my @weights;
for my $f (@files) {
    my $t = $code{$f};
    while ($t =~ /\.fontWeight\(((?:[^()]++|\((?1)\))*)\)/g) { (my $x = $1) =~ s/\s+//g; push @weights, short($f) . ':' . line_of($t, pos($t)) . "  .fontWeight($x)" }
}
my $mono = () = $all =~ /\.monospacedDigit\(\)/g;

# --- Simge, boşluk, metin (U0 yöntemi)
my %sym;
while ($all =~ /(?:systemName|systemImage|symbol):\s*"([^"]+)"/g) { $sym{$1} = 1 }
while ($all =~ /var symbol:[^{]*\{(.*?)\n    \}/sg) { my $b = $1; while ($b =~ /"([a-z0-9.]+)"/g) { $sym{$1} = 1 } }
while ($all =~ /Image\(systemName:\s*[^"\n]*\?\s*"([^"]+)"\s*:\s*"([^"]+)"/g) { $sym{$1} = 1; $sym{$2} = 1 }
my (%sp, %pad);
while ($all =~ /\bspacing:\s*(\d+(?:\.\d+)?)/g) { $sp{$1} = 1 }
while ($all =~ /\.padding\(([^()]*)\)/g) { my $a = $1; while ($a =~ /(?<![A-Za-z.])(\d+(?:\.\d+)?)/g) { $pad{$1} = 1 } }
my %texts;
for my $f (@files) { my $t = $raw{$f}; while ($t =~ /\bLF?\(\s*"((?:[^"\\]|\\.)*)"/g) { $texts{$1} = 1 } }

sub nums { join ' ', sort { $a <=> $b } keys %{$_[0]} }
my $n = @files;
print "UI ölçümü ($dir, $n dosya)\n";
printf "%-36s %d\n", "Button geçişi (toplam, §8)", $btn_total // 0;
printf "  %-34s %d\n", "ekranda", $btn{'ekranda'} // 0;
printf "  %-34s %d\n", "menü öğesi (açılır/sağ tık)", $btn{'menü'} // 0;
printf "  %-34s %d\n", "menü çubuğu (uygulama menüsü)", $btn{'menü çubuğu'} // 0;
printf "  %-34s %d\n", "diyalog (onay/uyarı)", $btn{'diyalog'} // 0;
my @w = map { "$_ ×$wrapper_calls{$_}" } sort keys %wrapper_calls;
printf "  %-34s %s\n", "düğmeli bileşen/yardımcı çağrısı", @w ? join(', ', @w) : '—';
printf "  %-34s %s\n", "dosya başına", join(', ', map { "$_ $btn_file{$_}" } sort { $btn_file{$b} <=> $btn_file{$a} || $a cmp $b } keys %btn_file);
printf "%-36s %d  [%s]\n", "onTapGesture eylemi (düğme değil)", scalar @taps, join(', ', @taps);
printf "%-36s %d  [%s]\n", "TextMenu tetikleyicisi", scalar @menus, join(', ', @menus);
printf "%-36s %d\n", "Eylem toplamı (Button+tap+TextMenu)", ($btn_total // 0) + @taps + @menus;
printf "%-36s %d\n", ".sheet/.popover geçişi", $sheets // 0;
printf "%-36s %d  [%s]\n", "Sayfa türü (sunulan görünüm)", scalar(keys %sheet_types), join(', ', sort keys %sheet_types);
printf "  %-34s %s\n", "türü bulunamayan sayfa", join(', ', @sheet_warn) if @sheet_warn;
printf "%-36s %d\n", "Onay diyaloğu (.confirmationDialog)", $dialogs;
printf "%-36s %d\n", "Uyarı (.alert)", $alerts;
printf "%-36s %d\n", "Sistem paneli (dosya seç/kaydet)", $panels;
printf "%-36s %d\n", "Farklı .font( ifadesi", scalar keys %fonts;
printf "  %-34s %d\n", "Design.Font dışı .font(", scalar @font_other;
print "    $_\n" for @font_other;
printf "  %-34s %d\n", ".fontWeight( çeşitlemesi", scalar @weights;
print "    $_\n" for @weights;
printf "  %-34s %d\n", ".monospacedDigit()", $mono;
printf "%-36s %d\n", "Farklı SF Symbol", scalar keys %sym;
printf "%-36s %d  [%s]\n", "Farklı spacing: sayısı", scalar(keys %sp), nums(\%sp);
printf "%-36s %d  [%s]\n", "Farklı .padding( sayısı", scalar(keys %pad), nums(\%pad);
printf "%-36s %d\n", "Benzersiz L(/LF( metni", scalar keys %texts;
PERL
