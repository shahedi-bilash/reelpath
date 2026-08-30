#!/usr/bin/perl
# ==========================================================================
# ReelPath -- rating-badge <-> TMDB ID sync (extract / apply)
# ==========================================================================
# Two modes, sharing one traversal so extraction and injection can never
# drift apart:
#
#   perl scripts/sync-rating-ids.pl --extract
#     Walks every in-scope page, finds every individual-title rating
#     badge that doesn't yet carry data-tmdb-id, and writes
#     scripts/_rating-manifest.json: one row per badge, in the exact
#     left-to-right order it appears in its file, with the title +
#     poster path needed to look it up. (gitignored -- scripts/*.json --
#     this is a working file, not a repo artifact.)
#
#   perl scripts/sync-rating-ids.pl --apply
#     Re-walks the same pages with the identical traversal, reads
#     scripts/_rating-resolved.json (produced by
#     scripts/resolve-tmdb-ids.ps1 in between the two Perl runs), and
#     injects data-tmdb-id="ID" data-media-type="movie|tv" into each
#     matching badge tag. Idempotent -- badges that already carry an id
#     are left untouched, so re-running after adding new content only
#     touches what's new.
#
# SCOPE: a rating badge is only in scope if it represents ONE specific
# movie/show with its own TMDB entry. That's:
#   .node-poster-wrap .rating-badge      (watch-order interactive nodes,
#                                          INCLUDING the homepage's own
#                                          copy of the MCU/Fate/Wan demo)
#   .entry-detail-img-wrap .rating-badge (watch-order full detail list)
#   .rank-plate .rating-badge            (best/ and lists/ rank items)
# Deliberately OUT of scope:
#   .hub-card--media .rating-badge -- franchise/list/genre-HUB cards
#     (MCU's 7.7, One Piece's 8.8, etc.), appearing both on hub pages
#     and as "More guides" cross-links on every watch-order page.
#   .card .rating-badge -- the homepage "Trending right now" rail links
#     to whole franchise guides and genre pages, not one title.
# Neither maps to a single TMDB entry, so neither gets a fabricated one;
# both stay hand-set.
# ==========================================================================
use strict; use warnings;
use JSON::PP;
use FindBin;
use File::Spec;

my $root = File::Spec->canonpath(File::Spec->catdir($FindBin::Bin, ".."));
my $mode = $ARGV[0] || '';
die "usage: perl sync-rating-ids.pl --extract|--apply\n" unless $mode eq '--extract' || $mode eq '--apply';

my @files;
push @files, "index.html";
opendir(my $wd, "$root/watch-order") or die $!;
push @files, map { "watch-order/$_" } grep { /\.html$/ } readdir($wd);
closedir $wd;
for my $sub (qw(one-piece naruto)) {
  push @files, "watch-order/$sub/filler-list.html" if -e "$root/watch-order/$sub/filler-list.html";
}
opendir(my $bd, "$root/best") or die $!;
push @files, map { "best/$_" } grep { /\.html$/ && $_ ne 'index.html' } readdir($bd);
closedir $bd;
opendir(my $ld, "$root/lists") or die $!;
push @files, map { "lists/$_" } grep { /\.html$/ && $_ ne 'index.html' } readdir($ld);
closedir $ld;

sub read_file {
  my $path = shift;
  open(my $fh, "<:raw", $path) or die "read $path: $!";
  local $/; my $c = <$fh>; close $fh;
  return $c;
}
sub write_file {
  my ($path, $content) = @_;
  open(my $fh, ">:raw", $path) or die "write $path: $!";
  print $fh $content;
  close $fh;
}

# Title source encoding is inconsistent site-wide (some alt/node-title
# text uses a raw literal "&", some uses the "&amp;" entity) -- normalize
# both to a literal "&" so TMDB search queries and the dedup key are
# consistent regardless of which form a given page happens to use.
sub esc_out {
  my $s = shift;
  # Literal raw UTF-8 bytes for the dashes, NOT \x{} escapes -- this file
  # is read/written entirely via :raw handles (untouched by Perl's UTF8
  # flag), and a \x{} escape in a double-quoted string DOES set that
  # flag on the substituted text, silently mixing flagged and unflagged
  # bytes in the same string. That mix forces Perl to re-encode the
  # WHOLE string as UTF-8 on output, corrupting every other multi-byte
  # character already in it -- hit and documented repeatedly elsewhere
  # in this project's build scripts. Literal bytes in the source avoid
  # the mixing entirely.
  $s =~ s/&ndash;/–/g; $s =~ s/&mdash;/—/g;
  $s =~ s/&quot;/"/g; $s =~ s/&#39;/'/g; $s =~ s/&gt;/>/g; $s =~ s/&lt;/</g;
  $s =~ s/&amp;/&/g; # must run last -- earlier substitutions can introduce literal & they shouldn't re-touch
  return $s;
}

# One shared walk: collect every relevant tag (poster img, title text,
# rating badge) as (position, kind, ...captures), sorted, then sweep
# left-to-right pairing each badge with the most recently seen poster
# and, when the poster's own alt is unusable (the trending-rail .card
# has alt=""), the nearest FOLLOWING title text instead.
sub walk_entries {
  my ($html) = @_;
  my @tok;

  # NOTE: the [^>]*? right before the optional alt group MUST be
  # non-greedy. A greedy [^>]* there finds the tag's closing ">" without
  # ever needing to backtrack into trying the optional alt group at all
  # (0 repetitions already satisfies the pattern), so alt silently comes
  # back undef even when it's present in the markup -- burned by this
  # once already in this same script (rank-plate alt was always undef,
  # silently masked everywhere except character-ranking Lists pages,
  # where it produced wrong titles like "Thanos" instead of "Avengers:
  # Endgame"). Non-greedy forces the earliest possible match, which is
  # the real alt attribute when one exists.
  while ($html =~ /<img\s+class="(node-poster|entry-detail-img|card-img|hub-card-img)"[^>]*\ssrc="https:\/\/image\.tmdb\.org\/t\/p\/w\d+(\/[^"]+)"[^>]*?(?:\salt="([^"]*)")?[^>]*>/g) {
    push @tok, { pos => $-[0], kind => 'img', cls => $1, poster => $2, alt => (defined $3 ? $3 : "") };
  }
  # .rank-plate posters have no distinguishing img class -- match by
  # parent context instead (img is always the rank-plate's first child).
  while ($html =~ /<div class="rank-plate[^"]*"><img\s+src="https:\/\/image\.tmdb\.org\/t\/p\/w\d+(\/[^"]+)"[^>]*?(?:\salt="([^"]*)")?[^>]*>/g) {
    push @tok, { pos => $-[0], kind => 'img', cls => 'rank-plate-img', poster => $1, alt => (defined $2 ? $2 : "") };
  }
  while ($html =~ /<(?:div|span) class="(card-title|rank-title|entry-detail-title|node-title)">([^<]+)<\/(?:div|span)>/g) {
    push @tok, { pos => $-[0], kind => 'title', text => $2 };
  }
  while ($html =~ /<span class="rating-badge(?: rating-badge--sm)?"((?:\s+data-tmdb-id="\d+")?(?:\s+data-media-type="(?:movie|tv)")?)>([\d.]+)<\/span>/g) {
    push @tok, { pos => $-[0], kind => 'badge', already => ($1 ? 1 : 0), value => $2, matchlen => length($&), matchtext => $& };
  }
  # data-node-type on the enclosing .node (MCU/Star Wars only) -- cheap
  # hint for the resolver to try /search/movie or /search/tv first.
  while ($html =~ /<div class="node[^"]*" data-node-type="(movie|series)"/g) {
    push @tok, { pos => $-[0], kind => 'nodehint', type => ($1 eq 'series' ? 'tv' : 'movie') };
  }

  @tok = sort { $a->{pos} <=> $b->{pos} } @tok;

  my @entries;
  my ($lastPoster, $lastAlt, $lastCls, $lastHint) = (undef, undef, undef, undef);
  for my $i (0 .. $#tok) {
    my $t = $tok[$i];
    if ($t->{kind} eq 'img') { $lastPoster = $t->{poster}; $lastAlt = $t->{alt}; $lastCls = $t->{cls}; next; }
    if ($t->{kind} eq 'nodehint') { $lastHint = $t->{type}; next; }
    if ($t->{kind} eq 'title') { next; } # consumed via forward-lookup below when needed
    if ($t->{kind} eq 'badge') {
      next unless defined $lastPoster;
      # Out of scope: franchise/hub-level ratings, not a single TMDB title.
      # card-img covers the homepage "Trending right now" rail, which
      # links to whole franchise guides and genre pages, not one title.
      next if $lastCls eq 'hub-card-img' || $lastCls eq 'card-img';

      my $title;
      my $altTrim = $lastAlt;
      $altTrim =~ s/\s+(poster|still)$// if $altTrim;
      if ($altTrim && length($altTrim) > 1) {
        $title = $altTrim;
      } else {
        # alt was empty (.card) -- look forward for the nearest title token.
        for my $j ($i + 1 .. $#tok) {
          if ($tok[$j]{kind} eq 'title') { $title = $tok[$j]{text}; last; }
          last if $tok[$j]{kind} eq 'img'; # ran into the next entry -- give up
        }
      }
      next unless $title;
      $title = esc_out($title);
      # Generic season/arc labels ("Season 1", "The Final Chapters") aren't
      # a distinct searchable title -- same rule as scripts/build-search-index.pl.
      next if $title =~ /^(?:The\s+)?(?:Final\s+)?Season\b|^The Final Chapters$|^Filler\b/i;
      push @entries, {
        pos => $t->{pos}, matchlen => $t->{matchlen}, matchtext => $t->{matchtext},
        already => $t->{already}, value => $t->{value},
        title => $title, poster => $lastPoster, hint => $lastHint,
      };
    }
  }
  return @entries;
}

if ($mode eq '--extract') {
  my @manifest;
  my $skippedAlready = 0;
  for my $rel (@files) {
    my $path = "$root/$rel";
    next unless -e $path;
    my $html = read_file($path);
    my @entries = walk_entries($html);
    my $idx = 0;
    for my $e (@entries) {
      if ($e->{already}) { $skippedAlready++; $idx++; next; }
      push @manifest, {
        file => $rel, ordinal => $idx, title => $e->{title}, poster => $e->{poster}, hint => $e->{hint},
      };
      $idx++;
    }
  }
  my $json = JSON::PP->new->utf8(0)->canonical(1)->encode({ entries => \@manifest });
  write_file("$root/scripts/_rating-manifest.json", $json);
  print "Extracted " . scalar(@manifest) . " badges needing an id (" . $skippedAlready . " already had one). Wrote scripts/_rating-manifest.json\n";
}
elsif ($mode eq '--apply') {
  my $resolvedRaw = read_file("$root/scripts/_rating-resolved.json");
  my $resolved = JSON::PP->new->decode($resolvedRaw); # { "title|poster" => {id, mediaType} or null }

  my $totalApplied = 0;
  my $totalUnresolved = 0;
  for my $rel (@files) {
    my $path = "$root/$rel";
    next unless -e $path;
    my $html = read_file($path);
    my @entries = walk_entries($html);
    my $idx = 0;
    my @edits; # {pos, matchlen, replacement}, applied back-to-front
    for my $e (@entries) {
      if (!$e->{already}) {
        my $key = "$e->{title}|$e->{poster}";
        my $r = $resolved->{$key};
        if ($r && $r->{id}) {
          my $newTag = $e->{matchtext};
          $newTag =~ s/(<span class="rating-badge(?: rating-badge--sm)?")>/$1 data-tmdb-id="$r->{id}" data-media-type="$r->{mediaType}">/;
          push @edits, { pos => $e->{pos}, len => $e->{matchlen}, repl => $newTag };
          $totalApplied++;
        } else {
          $totalUnresolved++;
        }
      }
      $idx++;
    }
    next unless @edits;
    @edits = sort { $b->{pos} <=> $a->{pos} } @edits; # back-to-front so earlier positions stay valid
    for my $ed (@edits) {
      substr($html, $ed->{pos}, $ed->{len}) = $ed->{repl};
    }
    write_file($path, $html);
  }
  print "Applied $totalApplied data-tmdb-id attributes. $totalUnresolved badges had no confident TMDB match (left unchanged, not guessed).\n";
}
