#!/usr/bin/perl
# ==========================================================================
# ReelPath -- search-index.json builder
# ==========================================================================
# Walks the site's own HTML and produces assets/search-index.json: the
# small, fast "do we already have a page for this" lookup the frontend
# uses to badge live TMDB search results (see /functions/search.js and
# mountSiteSearch() in assets/js/main.js). This index is NOT the primary
# search anymore -- it only tells the frontend "we have a curated page for
# this title" and supplies a couple of franchise acronyms (MCU, etc.)
# that would never appear as a real TMDB title to search against.
#
# Portable: resolves the repo root from this script's own location, so it
# runs unchanged locally (Windows, any cwd) and in GitHub Actions
# (ubuntu-latest ships Perl + JSON::PP -- both core modules, no install
# step needed). Safe to run repeatedly / on a schedule -- fully
# idempotent, only reads HTML and TMDB-hosted poster URLs already in it.
#
# HOW TO RUN:  perl scripts/build-search-index.pl
# ==========================================================================
use strict; use warnings;
use JSON::PP;
use FindBin;
use File::Spec;

my $root = File::Spec->canonpath(File::Spec->catdir($FindBin::Bin, ".."));
my @entries;

sub read_file {
  my $path = shift;
  open(my $fh, "<:raw", $path) or die "read $path: $!";
  local $/; my $c = <$fh>; close $fh;
  return $c;
}

sub esc_out { my $s = shift; $s =~ s/&amp;/&/g; $s =~ s/&#39;/'/g; return $s; }

# 1. Franchise guides (whole-page entries) -- from watch-order/*.html.
#    `aliases` covers acronyms/alt-names a visitor might type that never
#    appear as a substring of the display title itself (e.g. "MCU" is not
#    a substring of "Marvel Cinematic Universe") and would also never
#    come back from a live TMDB title search.
my @franchises = (
  ['one-piece.html','One Piece', ['OP']],
  ['mcu.html','Marvel Cinematic Universe', ['MCU']],
  ['fate.html','Fate Series', ['Fate']],
  ['wan-universe.html','The Conjuring / Wan Universe', ['Conjuring', 'The Conjuring Universe', 'Wan Universe']],
  ['naruto.html','Naruto', []],
  ['demon-slayer.html','Demon Slayer', ['Kimetsu no Yaiba']],
  ['star-wars.html','Star Wars', ['SW']],
  ['x-men.html','X-Men', []],
  ['fast-furious.html','Fast & Furious', ['Fast and Furious', 'F&F', 'The Fast and the Furious']],
  ['attack-on-titan.html','Attack on Titan', ['AOT', 'AoT', 'Shingeki no Kyojin', 'SNK']],
  ['harry-potter.html','Harry Potter', ['HP']],
);

# Franchises whose individual watch-order nodes are real, independently
# searchable titles (movies/seasons with their own TMDB entry) rather than
# generic saga/arc labels -- One Piece and Naruto use arc names ("East
# Blue", "Chunin Exams", "Filler arcs") that aren't titles anyone would
# search for, so they're deliberately left out of node-level indexing;
# their franchise-guide entry above still covers them.
my %index_nodes = map { $_ => 1 } qw(
  mcu.html star-wars.html x-men.html fast-furious.html fate.html
  wan-universe.html harry-potter.html demon-slayer.html attack-on-titan.html
);
# Safety net for the franchises above that still mix in generic
# season/arc labels (Demon Slayer's "Season 1", every Attack on Titan
# node) -- these aren't distinct searchable titles either, so skip them
# even though their franchise allows node-indexing.
my $generic_label = qr/^(?:The\s+)?(?:Final\s+)?Season\b|^The Final Chapters$|^Filler\b/i;

for my $f (@franchises) {
  my ($file, $name, $aliases) = @$f;
  my $html = read_file("$root/watch-order/$file");
  my ($poster) = $html =~ /<img class="node-poster" src="https:\/\/image\.tmdb\.org\/t\/p\/w500(\/[^"]+)"/;
  my $entry = {
    title => $name, type => "Franchise guide",
    url => "https://reelpath.pages.dev/watch-order/$file",
    poster => $poster ? "https://image.tmdb.org/t/p/w200$poster" : "",
  };
  $entry->{aliases} = $aliases if $aliases && @$aliases;
  push @entries, $entry;

  next unless $index_nodes{$file};

  # Split the page into per-node chunks on each node's opening tag, then
  # pull the poster + title out of each chunk independently -- more
  # robust against attribute-order drift than one giant multi-field regex.
  my @starts;
  while ($html =~ /<div class="node(?:(?: [a-z]+)*)"/g) { push @starts, $-[0]; }
  push @starts, length($html);
  for my $i (0 .. $#starts - 1) {
    my $chunk = substr($html, $starts[$i], $starts[$i + 1] - $starts[$i]);
    my ($poster2) = $chunk =~ /<img class="node-poster" src="https:\/\/image\.tmdb\.org\/t\/p\/w\d+(\/[^"]+)"/;
    my ($alt) = $chunk =~ /<img class="node-poster"[^>]*\salt="([^"]*)"/;
    my ($nodeTitle) = $chunk =~ /<div class="node-title">([^<]*)<\/div>/;
    next unless $poster2 && $nodeTitle;
    $alt =~ s/\s+(poster|still)$// if $alt;
    my $title = ($alt && length($alt) > 2) ? $alt : $nodeTitle;
    next if $title =~ $generic_label;
    push @entries, {
      title => esc_out($title), type => "Watch order pick",
      url => "https://reelpath.pages.dev/watch-order/$file",
      poster => "https://image.tmdb.org/t/p/w200$poster2",
    };
  }
}

# 2. List entries -- every rank-item row across lists/*.html (excluding index.html)
opendir(my $ld, "$root/lists") or die $!;
my @listFiles = grep { /\.html$/ && $_ ne 'index.html' } readdir($ld);
closedir $ld;
for my $file (sort @listFiles) {
  my $html = read_file("$root/lists/$file");
  while ($html =~ /<div class="rank-item[^"]*">.*?src="https:\/\/image\.tmdb\.org\/t\/p\/w\d+(\/[^"]+)"[^>]*>.*?<span class="rank-title">([^<]+)<\/span>/gs) {
    my ($poster, $title) = ($1, $2);
    push @entries, {
      title => esc_out($title), type => "List entry",
      url => "https://reelpath.pages.dev/lists/$file",
      poster => "https://image.tmdb.org/t/p/w200$poster",
    };
  }
}

# 3. Genre picks -- every rank-item row across best/*.html (excluding index.html)
opendir(my $bd, "$root/best") or die $!;
my @bestFiles = grep { /\.html$/ && $_ ne 'index.html' } readdir($bd);
closedir $bd;
for my $file (sort @bestFiles) {
  my $html = read_file("$root/best/$file");
  my %seen;
  while ($html =~ /<div class="rank-item[^"]*">.*?src="https:\/\/image\.tmdb\.org\/t\/p\/w\d+(\/[^"]+)"[^>]*>.*?<span class="rank-title">([^<]+)<\/span>/gs) {
    my ($poster, $title) = ($1, $2);
    my $key = "$title|$file";
    next if $seen{$key}++; # a title can legitimately repeat within Recent+Best-of-all-time; keep once per page
    push @entries, {
      title => esc_out($title), type => "Genre pick",
      url => "https://reelpath.pages.dev/best/$file",
      poster => "https://image.tmdb.org/t/p/w200$poster",
    };
  }
}

my $data = { generatedEntries => scalar(@entries), entries => \@entries };
my $json = JSON::PP->new->utf8(0)->canonical(1)->encode($data);
open(my $out, ">:raw", "$root/assets/search-index.json") or die $!;
print $out $json;
close $out;
print "Wrote " . scalar(@entries) . " entries to assets/search-index.json\n";
