package LexicalTranslationModel;

use strict;
use warnings;

use IO::Uncompress::Gunzip;
use IO::Uncompress::Bunzip2;

BEGIN {
    require Exporter;

    our $VERSION   = 1.0;
    our @ISA       = qw(Exporter);
    our @EXPORT    = qw(get_lexical);
    our @EXPORT_OK = qw();

}

sub get_lexical {
    my ($alignment_file_f,$alignment_file_e,$alignment_file_a,$lexical_file,$write_counts,$baseline_corpus_f,$baseline_corpus_e,$baseline_alignment, $instance_weights_file) = @_;
    print STDERR "($alignment_file_f,$alignment_file_e,$lexical_file)\n";
    print STDERR "baseline ($baseline_corpus_f,$baseline_corpus_e,$baseline_alignment)\n" if defined $baseline_alignment;
    print STDERR "instance weights ($instance_weights_file)\n" if defined $instance_weights_file;
#    my $alignment_file_a = $___ALIGNMENT_FILE.".".$___ALIGNMENT;


    if (-e "$lexical_file.f2e" && -e "$lexical_file.e2f" && (!$write_counts || -e "$lexical_file.counts.f2e" && -e "$lexical_file.counts.e2f")) {
      print STDERR "  reusing: $lexical_file.f2e and $lexical_file.e2f\n";
      return;
    }

    my (%WORD_TRANSLATION,%TOTAL_FOREIGN,%TOTAL_ENGLISH);
    &get_lexical_counts($alignment_file_e,$alignment_file_f,$alignment_file_a,$instance_weights_file,\%WORD_TRANSLATION,\%TOTAL_FOREIGN,\%TOTAL_ENGLISH);
    if (defined($baseline_alignment)) {
      &get_lexical_counts($baseline_corpus_e,$baseline_corpus_f,$baseline_alignment,undef,\%WORD_TRANSLATION,\%TOTAL_FOREIGN,\%TOTAL_ENGLISH);
    }

    open(F2E,">$lexical_file.f2e") or die "ERROR: Can't write $lexical_file.f2e";
    open(E2F,">$lexical_file.e2f") or die "ERROR: Can't write $lexical_file.e2f";
    if ($write_counts) {
        open(F2E2,">$lexical_file.counts.f2e") or die "ERROR: Can't write $lexical_file.counts.f2e";
        open(E2F2,">$lexical_file.counts.e2f") or die "ERROR: Can't write $lexical_file.counts.e2f";
    }

    foreach my $f (keys %WORD_TRANSLATION) {
	foreach my $e (keys %{$WORD_TRANSLATION{$f}}) {
	    printf F2E "%s %s %.7f\n",$e,$f,$WORD_TRANSLATION{$f}{$e}/$TOTAL_FOREIGN{$f};
	    printf E2F "%s %s %.7f\n",$f,$e,$WORD_TRANSLATION{$f}{$e}/$TOTAL_ENGLISH{$e};
	    if ($write_counts) {
	        printf F2E2 "%s %s %i %i\n",$e,$f,$WORD_TRANSLATION{$f}{$e},$TOTAL_FOREIGN{$f};
	        printf E2F2 "%s %s %i %i\n",$f,$e,$WORD_TRANSLATION{$f}{$e},$TOTAL_ENGLISH{$e};
	    }
	}
    }
    close(E2F);
    close(F2E);
    if ($write_counts) {
        close(E2F2);
        close(F2E2);
    }
    print STDERR "Saved: $lexical_file.f2e and $lexical_file.e2f\n";
}

sub get_lexical_counts {
    my ($alignment_file_e,$alignment_file_f,$alignment_file_a,$instance_weights_file,$WORD_TRANSLATION,$TOTAL_FOREIGN,$TOTAL_ENGLISH) = @_;
	my ($E, $F, $A);
	-e "$alignment_file_e.gz" ?
	$E = new IO::Uncompress::Gunzip("$alignment_file_e.gz") :
	(-e "$alignment_file_e.bz2" ? $E = new IO::Uncompress::Bunzip2("$alignment_file_e.bz2") : open $E, "<$alignment_file_e")
	or die "ERROR: Can't read $alignment_file_e";
	-e "$alignment_file_f.gz" ?
	$F = new IO::Uncompress::Gunzip("$alignment_file_f.gz") :
	(-e "$alignment_file_f.bz2" ? $F = new IO::Uncompress::Bunzip2("$alignment_file_f.bz2") : open $F, "<$alignment_file_f")
	or die "ERROR: Can't read $alignment_file_f";
	-e "$alignment_file_a.gz" ?
	$A = new IO::Uncompress::Gunzip("$alignment_file_a.gz") :
	(-e "$alignment_file_a.bz2" ? $A = new IO::Uncompress::Bunzip2("$alignment_file_a.bz2") : open $A, "<$alignment_file_a")
	or die "ERROR: Can't read $alignment_file_a";
    my $W = undef;
    if (defined($instance_weights_file) && $instance_weights_file) {
      open($W, $instance_weights_file) or die "ERROR: Can't read $instance_weights_file";
    }

    my $alignment_id = 0;
    while(my $e = <$E>) {
        if (($alignment_id++ % 1000) == 0) { print STDERR "!"; }
        chomp($e); $e =~ s/^\s+//;
        my @ENGLISH = split(/[ \t]/,$e);
        my $f = <$F>; chomp($f); $f =~ s/^\s+//;
        my @FOREIGN = split(/[ \t]/,$f);
        my $a = <$A>; chomp($a);  $a =~ s/^\s+//;
        my $iw = 1; # instance weight
        $iw = <$W> if defined $W;
        my (%FOREIGN_ALIGNED,%ENGLISH_ALIGNED);
        foreach (split(' ',$a)) {
            my ($fi,$ei) = split(/\-/);
	    if ($fi >= scalar(@FOREIGN) || $ei >= scalar(@ENGLISH)) {
		print STDERR "alignment point ($fi,$ei) out of range (0-$#FOREIGN,0-$#ENGLISH) in line $alignment_id, ignoring\n";
	    }
	    else {
		# local counts
		$FOREIGN_ALIGNED{$fi}+=$iw;
		$ENGLISH_ALIGNED{$ei}+=$iw;
		
		# global counts
		$$WORD_TRANSLATION{$FOREIGN[$fi]}{$ENGLISH[$ei]}+=$iw;
		$$TOTAL_FOREIGN{$FOREIGN[$fi]}+=$iw;
		$$TOTAL_ENGLISH{$ENGLISH[$ei]}+=$iw;
	    }
        }

        # unaligned words
        for(my $ei=0;$ei<scalar(@ENGLISH);$ei++) {
          next if defined($ENGLISH_ALIGNED{$ei});
          $$WORD_TRANSLATION{"NULL"}{$ENGLISH[$ei]}+=$iw;
          $$TOTAL_ENGLISH{$ENGLISH[$ei]}+=$iw;
          $$TOTAL_FOREIGN{"NULL"}+=$iw;
        }
        for(my $fi=0;$fi<scalar(@FOREIGN);$fi++) {
          next if defined($FOREIGN_ALIGNED{$fi});
          $$WORD_TRANSLATION{$FOREIGN[$fi]}{"NULL"}+=$iw;
          $$TOTAL_FOREIGN{$FOREIGN[$fi]}+=$iw;
          $$TOTAL_ENGLISH{"NULL"}+=$iw;
        }
    }
    print STDERR "\n";
}

END {
}

1;
