#!/usr/bin/perl -w
use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use FindBin qw($Bin $Script);
use File::Basename qw(basename dirname);
my $BEGIN_TIME=time();
my $version="1.0.0";
require "$Bin/path.pm";
#######################################################################################

# ------------------------------------------------------------------
# GetOptions
# ------------------------------------------------------------------
our ($VCF_dbSNP, $REF_HG19);
my ($ftarget, $fkey,$outdir, $NoFilter);
my $fref = $REF_HG19;
my $fdatabase = $REF_HG19;
my $step = 1;
my $para_num = 10;
my $stm = 45;
my $opt_tm=65;
my $opt_tm_probe=75;

my $rfloat = 0.2;
my $dis_aver = 500;
my $size_range="100,150,70,200"; ## product size range(best_min, best_max, min, max)
my $pos_range; ## pos range(best_min, best_max, min, max)
my $range_len="18,28,2";
my $dis_range; ## distance between primers range, required when design non face-to-face primer
my $type = "face-to-face:SNP";
my $ctype = "Single";
my $onum = 3;
my ($dimer_check, $homology_check, $SNP_check);
my $averTLen;
my $probe;
my $regions;
GetOptions(
				"help|?" =>\&USAGE,
				"it:s"=>\$ftarget,
				"ir:s"=>\$fref,
				"id:s"=>\$fdatabase,
				"p:s"=>\$fkey,
				"tlen:s"=>\$averTLen,
				"dimer_check:s"=>\$dimer_check,
				"homology_check:s"=>\$homology_check,
				"SNP_check:s"=>\$SNP_check,
				"NoFilter:s"=>\$NoFilter,

				## primer design
				"opttm:s"=>\$opt_tm,
				"opttmp:s"=>\$opt_tm_probe,
				"regions:s"=>\$regions,
				"rlen:s"=>\$range_len,
				"rdis:s"=>\$dis_range,
				"rsize:s"=>\$size_range,
				"rpos:s"=>\$pos_range,

				"type:s"=>\$type,
				"ctype:s"=>\$ctype,
				"probe:s"=>\$probe,
				"ds:s"=>\$dis_aver,
				"rf:s"=>\$rfloat,
				"on:s"=>\$onum,

				"stm:s"=>\$stm,
				"para:s"=>\$para_num,
				"od:s"=>\$outdir,
				) or &USAGE;
&USAGE unless ($ftarget and $fdatabase and $fkey);
$outdir||="./";
`mkdir $outdir`	unless (-d $outdir);
$outdir=AbsolutePath("dir",$outdir);
my ($score_dis, $score_pos)=(10,10);
my ($min_len, $max_len, $scale_len)=split /,/, $range_len;
my $choose_num = 5; ## for a primer, at least $choose_num primers can be selected as its pair.
my $pnum = 50; ## position num for one primer, its candidate primers num is roughly: pnum*(maxl-minl)/scalel.
my $sh;
open($sh, ">$outdir/$fkey.sh") or die $!;

if(defined $probe && $max_len<35){
	die "Too small oligo length to design probe! $range_len\n";
}

if($type=~/face-to-face/){
	$dis_range = $size_range;
}else{
	if(!defined $dis_range){
		die "Wrong: -rdis must be given when primer type is not face-to-face!\n";
	}
}

### get template file
my $ftemplate;
my $ftype;
my $head = `head -1 $ftarget`;
chomp $head;
if($head=~/^>/){
	$ftype = "fasta";
	$ftemplate = $ftarget;
}else{
	$ftype = "SNP";
	my @unit = split /\s+/, $head;
	my $cnum = scalar @unit;
	if($cnum == 1 && $head=~/rs\d+/){
		&Run("perl $Bin/extract_by_id.pl -i $VCF_dbSNP -l $ftarget -k $fkey.SNP -c 2 -od $outdir", $sh);
		&Run("less $outdir/$fkey.SNP.extract|awk '{print \"chr\"\$_}' > $outdir/$fkey.target.txt", $sh);
		$ftarget = "$outdir/$fkey.target.txt";
	}elsif($cnum < 5){
		die "Wrong input target file: $ftarget\n";
	}
}
if($ftype eq "SNP"){
	my $extend_len;
	my @rdiss = split /,/, $dis_range;
	$extend_len = (int(($rdiss[-1]+$max_len+10)/100)+1) * 100;
	
	if(!defined $pos_range){
		die "Wrong: -rpos must be given when -it SNP file!\n";
	}
	my ($optmin, $optmax, $min, $max) = split /,/, $pos_range;
	my $md = int (($max+$optmax)/2) - $optmin;
	&Run("perl $Bin/get_template.pl -i $ftarget -r $fref -k $fkey -et $extend_len -md $md -od $outdir/ --dieC", $sh);
	$ftemplate = "$outdir/$fkey.template.fa";
}

### homology check
if(defined $homology_check){
	&Run("perl $Bin/homology_check.pl -it $ftemplate -ir $fref -k $fkey -od $outdir/homology_check", $sh);
}
### primer design
my ($rdis1, $fdis1, $rdis2, $fdis2);
if(defined $regions){
	my @reg=split /;/, $regions;
	($fdis1, $rdis1)=$reg[0]=~/([3,5]):(\S+)/;
	## check 
	if($type eq "face-to-face:Region" || $type eq "back-to-back"){
		if(scalar @reg==1){ 
			die "Wrong: No rdis2! -regions $regions must with two region seperate by semicolon when type is face-to-face:Region and back-to-back!";
		}else{
			($fdis2, $rdis2)=$reg[1]=~/([3,5]):(\S+)/;
		}
	}
}else{
	($rdis1, $fdis1, $rdis2, $fdis2)=&caculate_rdis($dis_range, $pos_range, $type, $min_len, $max_len);
}
print "region range to design primers: ", join("\t", $fdis1.";".$rdis1, defined $fdis2? $fdis2.";".$rdis2:""),"\n";
my ($stype)=split /:/, $type;
my $dcmd = "perl $Bin/primer_design.pl -i $ftemplate -r $fdatabase -type $stype -opttm $opt_tm -rlen $range_len -fdis $fdis1 -rdis $rdis1 -stm $stm -para $para_num -k $fkey -od $outdir/design";
if(defined $NoFilter){
	$dcmd .= " --NoFilter";
}
if(defined $probe){
	$dcmd.=" -opttmp $opt_tm_probe";
}
&Run($dcmd, $sh);

if($type eq "face-to-face:Region" || $type eq "back-to-back"){
	my $dir_rev = "$outdir/design_rev";
	`mkdir $dir_rev` unless(-d $dir_rev);
	my $fname = basename($ftemplate);
	open(O, ">$dir_rev/$fname\_rev") or die $!;
	open(I, $ftemplate) or die $!;
	$/=">";
	while(<I>){
		chomp;
		next if(/^$/);
		my ($head, @seq)=split /\n/, $_;
		my ($id)=split /\s+/, $head;
		my $seq = join ("", @seq);
		$seq =~tr/ATCGatcg/TAGCtagc/;
		$seq = reverse $seq;
		print O ">$id\_rev\n";
		print O $seq,"\n";
	}
	close(O);
	close(I);
	$/="\n";
	
	if($rdis2 eq ""){
		die "No rdis2!\n";
	}
	my $dcmd = "perl $Bin/primer_design.pl -i $dir_rev/$fname\_rev -r $fdatabase -type $stype -opttm $opt_tm -rlen $range_len -fdis $fdis2 -rdis $rdis2 -stm $stm -para $para_num -k $fkey\_rev -od $dir_rev";
	if(defined $NoFilter){
		$dcmd .= " --NoFilter";
	}
	if(defined $probe){
		$dcmd.=" -opttmp $opt_tm_probe";
	}
	&Run($dcmd, $sh);
}


### select primer pair
my $score_dis_range = $score_dis.",".$dis_range;
my $cmd = "perl $Bin/primer_pair_select.pl -i $outdir/design/$fkey.primer.score -it $ftemplate -k $fkey -rd $score_dis_range  -od $outdir -tp $type -ct $ctype";
if(defined $pos_range){
	my $score_pos_range = $score_pos.",".$pos_range;
	$cmd .= " -rp $score_pos_range";
}
if($type eq "face-to-face:Region" || $type eq "back-to-back"){
	$cmd .= " -ir $outdir/design_rev/$fkey\_rev.primer.score";
}
if($ctype eq "Full-covered"){
	$cmd .= " -ds $dis_aver -rf $rfloat";
}else{
	$cmd .= " -on $onum";
}
&Run($cmd, $sh);

### specificity re-evaluation
my $dir_re = "$outdir/re_evalue";
`mkdir $dir_re` unless(-e $dir_re);
&Run("less $outdir/$fkey.final.result |perl -ne '{chomp; \@a=split; if(\$_=~/-P1/){print \$a[3],\"\\t\", \$a[4];}elsif(\$_=~/-P2/){ print \"\\t\", \$a[4],\"\\n\";}}'|less >$dir_re/$fkey.primer.pair.list", $sh);
my @diss = split /,/, $dis_range;
my $extend = $diss[-1]*2;
$cmd = "perl $Bin/primer_evaluation.pl -p $dir_re/$fkey.primer.pair.list -d $fref -n 2 -k $fkey\_pair --NoFilter -type $stype -rdis $size_range -opttm $opt_tm -stm $stm -od $dir_re";
&Run($cmd, $sh);


### primers dimer check
if(defined $dimer_check){
	&Run("perl $Bin/cross_dimer_check.pl -i $outdir/$fkey.final.result -k $fkey -od $outdir/dimer_check", $sh);
}

### select probe
if(defined $probe){
	my $fprobe;
	if($type eq "face-to-face:Region"){
		$fprobe="$outdir/design/$fkey.primer.score,$outdir/design_rev/$fkey\_rev.primer.score";
	}elsif($type eq "face-to-face:SNP"){
		$fprobe="$outdir/design/$fkey.primer.score";
	}else{
		die "Wrong: the type is not face-to-face, Can't design probe!\n";
	}
	&Run("perl $Bin/probe_select.pl -ip $outdir/$fkey.final.result -it $ftemplate -io $fprobe -k $fkey.final.result -opttm $opt_tm_probe -minl $min_len -maxl $max_len -od $outdir", $sh);
	`mv $outdir/$fkey.final.result.probe $outdir/$fkey.final.result`;
}




#######################################################################################
print STDOUT "\nDone. Total elapsed time : ",time()-$BEGIN_TIME,"s\n";
#######################################################################################

# ------------------------------------------------------------------
# sub function
# ------------------------------------------------------------------

sub caculate_rdis{
	my ($dis_range, $pos_range, $type, $minl, $maxl)=@_;
	## caculate -rdis parameter
	my ($bmind, $bmaxd, $mind, $maxd)=split /,/, $dis_range;
	my @region; ##  two-dimensional array, @{region[1]} is regions of revcom template sequence
	my $alen = int(($minl+$maxl)/2);
	my ($min, $max, $size, $index, $fdis1, $fdis2); #fdis: distance caculation format, 3: from primer right end to template 3'end; 5: from left right end to template 5'end
	my $step0 = int(($bmaxd-$bmind)/$choose_num)+1; ## max step for distance range $dis_range
	if(defined $pos_range){
		my ($bminp, $bmaxp, $minp, $maxp)=split /,/, $pos_range;
		$fdis1 = 3;
		push @{$region[0]}, ($minp, $maxp, int(($maxp-$minp)/$pnum)+1);
		if($type eq "face-to-face:SNP"){
			$min = $mind-$maxp-2*$alen;
			$max = $maxd-$minp-2*$alen;
			$fdis1 = 3;
			$index = 0;
		}elsif($type eq "back-to-back"){
			$min = $minp+$alen-$maxd;
			$max = $maxp+$alen-$mind;
			$fdis2 = 5; # from left right end to template 5'end
			$index = 1;
		}elsif($type eq "Nested"){
			$min = $maxp+$mind;
			$max = $maxp+$maxd;
			$fdis1 = 3;
			$index = 0;
		}else{
			die "Wrong type when defined -srpos, must be one of (face-to-face:SNP, back-to-back, Nested)!\n";
		}
		my $posnum = int(($max-$min+1)/$step0);
		if($posnum > $pnum*2){ ## check step is small enough to keep $choose_num primers to be selected as its pairs for one primer
			die "Step size $step0 in region $min-$max produces too many primers, which will take too long to design! Please narrow -rpos $pos_range, or magnify -rdis $dis_range!\n";
		}
		$min=$min<$maxp? $maxp: $min;
		push @{$region[$index]}, ($min, $max, $step0);
	}else{
		if(!defined $averTLen){
			die "-tlen must be given when not defined -rpos!\n";
		}
		if($type eq "face-to-face:Region"){## usually is generic:Region
			$min = $mind - $alen;
			$max = $averTLen - $alen;
			my $posnum = int(($max-$min+1)/$step0);
			if($ctype eq "Single" && $posnum > $pnum*2){ ## check step is small enough to keep $choose_num primers to be selected as its pairs for one primer
				print "Step size $step0 in region $min-$max produces too many primers, which will take too long to design! then narrow region to ";
				my $d0 = ($step0-1)*$pnum;
				my $x = ($max-$min-$d0)/2; ## size of range(min-max) to cutdown
				$max = $max - $x;
				$min = $min + $x;
				print "$min-$max.\n";
			}
			if($ctype eq "Full-covered"){
				my $npair = int (($averTLen-$mind)/$dis_aver);
				if($posnum > ($pnum/2)*$npair*2){ ## check 
					die "Step size $step0 in region $min-$max produces too many primers, which will take too long to design!Please magnify -rdis $dis_range!\n";
				}
			}
			#($fdis1, $fdis2) = (3, 3);
			($fdis1, $fdis2) = (5, 3); ## fdis1: count from left on forward template; fdis2: count from right on backward template.
			$min=$min<0? 0: $min;
			push @{$region[0]}, ($min, $max, $step0);
			push @{$region[1]}, ($min, $max, $step0);
		}else{ ## Full-covered only support "face-to-face:Region"
			die "Wrong type when not defined -srpos, only can be (face-to-face:Region)!\n";
		}
	}
	my $rdis1 = join(",", @{$region[0]});
	my $rdis2 = scalar @region==2? join(",", @{$region[1]}): "";
	return ($rdis1, $fdis1, $rdis2, $fdis2);
}

sub Run{
    my ($cmd, $sh, $nodie)=@_;
	print $sh $cmd,"\n";
	print "###", $cmd,"\n";
    my $ret = system($cmd);
    if (!defined $nodie && $ret) {
        die "Run $cmd failed!\n";
    }
}

sub AbsolutePath
{		#获取指定目录或文件的决定路径
		my ($type,$input) = @_;

		my $return;
		if ($type eq 'dir')
		{
				my $pwd = `pwd`;
				chomp $pwd;
				chdir($input);
				$return = `pwd`;
				chomp $return;
				chdir($pwd);
		}
		elsif($type eq 'file')
		{
				my $pwd = `pwd`;
				chomp $pwd;

				my $dir=dirname($input);
				my $file=basename($input);
				chdir($dir);
				$return = `pwd`;
				chomp $return;
				$return .="\/".$file;
				chdir($pwd);
		}
		return $return;
}

sub GetTime {
	my ($sec, $min, $hour, $day, $mon, $year, $wday, $yday, $isdst)=localtime(time());
	return sprintf("%4d-%02d-%02d %02d:%02d:%02d", $year+1900, $mon+1, $day, $hour, $min, $sec);
}


sub USAGE {#
	my $usage=<<"USAGE";
Program:
Version: $version
Contact:zeng huaping<huaping.zeng\@genetalks.com> 

    ############## PrimerScore pipeline  ################

    ###input file(target spot file) format:
     format 1(rdID list):
		 rs144701072
		 rs10794507
		 rs2245135
		 rs13127915
		 rs4620658
     format 2(first 5 columns of vcf format):
		 chr14    94847286     rs121912714	T              A
		 chr15    44859635     rs312262781	CTCAA          C
		 chr17    40695468     rs104894596	C              T
		 chr12    102855239    PAH_603T_G	A              C
		 chr12    102912801    PAH_158G_A	C              T

    ###-rdis: distance range of pair primers, (best_min, best_max, min, max) separted by ",", example:
   		
 	note: P1/P2 is distance from primer1/primer2 3'end to SNP or template 3'end.
		  L1/L2 is length of primer1/primer2, L is length of template sequence.

      face-to-face: |---> P1 x            dis_range(P1+L1+Lt+P2+L2):100,150,70,200(qPCR); 530,570,500,600(Sanger)
         (SNP)               x  P2 <---|  (Lt is scale length of target spots)

      face-to-face: P1 |--->        x     dis_range(P1+L1+P2+L2-L):100,150,70,200(qPCR)
        (Region)     x        <---| P2    (L is length of template sequence)
                     ________________

      back-to-back:  x <---| P2           dis_range(P1+L1+P2+L2-L):5,10,0,15
                      P1 |---> x          (Overlap between p1 and p2: dis > 0)
                     __________

      back-to-back:  x <---| P2           dis_range(P1+L1+P2+L2-L):-50,-40,-60,-30
                           P1 |---> x     (No overlap between p1 and p2: dis < 0)
                     _______________

            Nested: P2 --->|   x          dis_range(P2-P1):10,15,5,30
                      P1 --->| x



Usage:
  Options:
  -it  <file>   Input target file(SNP file or template fasta file), forced
  -ir  <file>   Input reference file to extract template sequence of SNP, needed when target file(-it) is SNP file, [$fref]
  -id  <file>   Input database file to check specificity, [$fdatabase] 
  -p   <str>    prefix of output file, forced
  -tlen <int>   template average length, must be given when -type is face-to-face:Region
  --probe             design probe when -type "face-to-face", optional
  --NoFilter          Not filter any primers
  --homology_check    check homologous sequence of template sequence when design for NGS primers, optional
  --dimer_check       check cross dimers among selected primers, optional
  --SNP_check         check common SNP covered by selected primer sequence and modify to degenerated base, optional

  ### design parameters
  -opttm    <int>     optimal tm of primer, [$opt_tm]
  -opttmp   <int>     optimal tm of probe, [$opt_tm_probe]
  -rlen     <str>     oligo len range and scale (start,end,scale), start <= end, [$range_len]
  -rpos     <str>     position range, distance of p1 to the detected site, (opt_min, opt_max, min, max) separted by ",", must be given when -it is SNP file
  -rsize    <str>     product size range (opt_min, opt_max, min, max), separted by ",", [$size_range]
  -rdis     <str>     distance range between pair primers, required when -type is not "face-to-face", (opt_min, opt_max, min, max) separted by ",", optional
  -regions  <str>     interested regions of candidate primers walking on, format is "3/5:start,end,scale,start2,end2,scale2...", 3:count from primer right to template 3end, 5:count from primer left to template 5end; two regions seperated by ";" when type is face-to-face:Region and back-to-back; if not given, will caculate automatically, optional

  ### 
  -type   <str>     primer type, "face-to-face:SNP", "face-to-face:Region", "back-to-back", "Nested", ["face-to-face:SNP"]
  -ctype  <str>     primer covered type, "Single" or "Full-covered", ["Single"]
     -ds  <int>     average distance between adjacent primers when -ctype "Full-covered", [500]
     -rf  <float>   ratio of distance between adjacent primers can float when -ctype "Full-covered", [0.2]
     -on  <int>     output num when -ctype "Single",[$onum]

  -stm     <int>      min tm to be High_tm in specifity, [$stm]
  -para  <int>      parallel num, [$para_num]
  -od    <dir>      Dir of output file, default ./
  -h                Help

USAGE
    print $usage;
    exit;
}

