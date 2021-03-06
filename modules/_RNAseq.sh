###########################################
# bash script for running paired-end RNAseq
# author: Xianjun Dong
# email: xdong@rics.bwh.harvard.edu
# date: 9/16/2013
# version: 2.0
# Note: call this script in the folder of fastq file
###########################################
#!/bin/bash

if [ $# -ne 2 ]
then
  echo "Usage: $0 HC_BN10-39_2.R1.fastq.gz HC_BN10-39_2.R2.fastq.gz"
  exit
fi

###########################################
echo "["`date`"] STEP 1. Configuring"
###########################################

modulename=`basename $0`
set +o posix  #  enables the execution of process substitution e.g. http://www.linuxjournal.com/content/shell-process-redirection

R1=$1  # filename of R1 
R2=$2  # filename of R2 (for paired-end reads)
samplename=${R1/[.|_]R1*/}

pipeline_path=$HOME/neurogen/pipeline/RNAseq
source $pipeline_path/config.txt

inputdir=$PWD
outputdir=$inputdir/../run_output
[ -d $outputdiri/$samplename ] || mkdir -p $outputdir/$samplename

###########################################
echo "["`date`"] STEP 2. quality filter: adaptor removal/clip"
###########################################

##### adaptor removal
[ -d $inputdir/../filtered ] || mkdir $inputdir/../filtered

[ -e $inputdir/../filtered/adaptor.fa ] || echo -e ">Truseq_complementary_part_3p\nAGATCGGAAGAGC" > $inputdir/../filtered/adaptor.fa

[ ! -f $outputdir/$samplename/.status.$modulename.adaptorremoval ] && \
fastq-mcf -o $inputdir/../filtered/$R1 -o $inputdir/../filtered/$R2 -t 0 -x 10 -l 15 -w 4 -u $inputdir/../filtered/adaptor.fa <(zcat $R1) <(zcat $R2) && \
touch $outputdir/$samplename/.status.$modulename.adaptorremoval 

cd $inputdir/../filtered

#############################################
echo "["`date`"] STEP 2.1. extract short reads (e.g. <=37nt, R1/R2 same length and reverse complementary)"
############################################
[ -d $inputdir/../filtered/shortReads ] || mkdir $inputdir/../filtered/shortReads

[ ! -f $outputdir/$samplename/.status.$modulename.shortReadsExtract ] && \
#zcat $R1 | perl -ne '$h=$_; $s=<>; $a=<>; $ss=<>; print "$h$s$a$ss" if(length($s)<=31);' | gzip > shortReads/$R1 
#zcat $R2 | perl -ne '$h=$_; $s=<>; $a=<>; $ss=<>; print "$h$s$a$ss" if(length($s)<=31);' | gzip > shortReads/$R2 
join -j 1 <(zcat $R1 | perl -ne 'chomp;$h=$_;chomp($s=<>);chomp($a=<>);$ss=<>; print "$h\t$s\t$a\t$ss" if(length($s)<=37);' | sort -k1,1) <(zcat $R2 | perl -ne 'chomp;$h=$_;chomp($s=<>);chomp($a=<>);$ss=<>; print "$h\t$s\t$a\t$ss" if(length($s)<=37);' | sort -k1,1) | perl -ne '@a=split;$rcs=reverse($a[2]);$rcs=~tr/ACGTacgt/TGCAtgca/; print ">$a[0]\n$a[2]\n" if($rcs eq $a[6]);' | gzip > shortReads/${R1/R1.fastq/fasta} && \
touch $outputdir/$samplename/.status.$modulename.shortReadsExtract 

[ ! -f $outputdir/$samplename/.status.$modulename.shortReadsExtract_stemloop ] && \
zcat shortReads/${R1/R1.fastq/fasta} | perl -ne '$h=$_; $s=<>; chomp($s); $sub=reverse(substr($s,-6)); $sub=~tr/ACGTacgt/TGCAtgca/; print "$h$s\n" if($s!~/GCGCGCGCGC/ && (substr($s,0,6) eq $sub));' | gzip > shortReads/${R1/R1.fastq/fasta.stemloop} && \
touch $outputdir/$samplename/.status.$modulename.shortReadsExtract_stemloop

#############################################
echo "["`date`"] STEP 3. QC"
############################################

[ ! -f $outputdir/$samplename/.status.$modulename.fastqc ] && \
fastqc --outdir $outputdir/$samplename --extract -t 2 $R1 $R2 && \
rm $outputdir/$samplename/*fastqc.zip && \
touch $outputdir/$samplename/.status.$modulename.fastqc 

############################################
echo "["`date`"] STEP 4. mapping"
############################################
## tophat (output accepted_hits.sam, allow up to 100 multiple hits)
## TODO: 1) use offrated index genome_offrate3;
## Note: GATK requires @RG group has fields of ID, SM, PL, LB, PU

## NOTE: this was done for all batch 1-5 samples with tophat version 2.0.8
[ ! -f $outputdir/$samplename/.status.$modulename.mapping ] && \
tophat -o $outputdir/$samplename --no-convert-bam --rg-id $samplename --rg-sample $samplename --rg-platform ILLUMINA --rg-library $samplename --rg-platform-unit $samplename --keep-fasta-order -p $CPU --read-mismatches $mm $tophat $PE_option $strand_option --max-multihits $MAX_HIT --no-coverage-search genome $R1 $R2 && \
touch $outputdir/$samplename/.status.$modulename.mapping

#[ ! -f $outputdir/$samplename/.status.$modulename.smallRNAmapping ] && \
#tophat -o $outputdir/$samplename --no-convert-bam --rg-id $samplename --rg-sample $samplename --rg-platform ILLUMINA --rg-library $samplename --rg-platform-unit $samplename --keep-fasta-order -p $CPU --read-mismatches $mm $tophat $PE_option $strand_option --max-multihits $MAX_HIT --no-coverage-search genome $R1 $R2 && \
#touch $outputdir/$samplename/.status.$modulename.smallRNAmapping

# circular RNA calling and quantification (see: https://github.com/YangLab/CIRCexplorer/blob/master/README.md)
## using tophat-2.0.10 as suggested by CIRCexplorer
[ ! -f $outputdir/$samplename/.status.$modulename.circRNA ] && \
#bamToFastq -i $outputdir/$samplename/unmapped.bam -fq $outputdir/$samplename/unmapped.fastq && 
tophat -o $outputdir/$samplename/tophat_fusion -p $CPU --fusion-search --keep-fasta-order --bowtie1 --no-coverage-search $BOWTIE_INDEXES/genome $outputdir/$samplename/unmapped.fastq && \
CIRCexplorer.py -f $outputdir/$samplename/tophat_fusion/accepted_hits.bam -g $GENOME/Sequence/WholeGenomeFasta/genome.fa -r $GENOME/Annotation/Genes/refFlat.txt && \
touch $outputdir/$samplename/.status.$modulename.circRNA

###########################################
echo "["`date`"] STEP 5. post-processing, format converting"
###########################################

cd $outputdir/$samplename

[ ! -f .status.$modulename.sam2bam ] && \
samtools view -Sbut $BOWTIE2_INDEXES/genome.fai accepted_hits.sam | samtools sort - accepted_hits.sorted && \
mv accepted_hits.sorted.bam accepted_hits.bam && \
samtools index accepted_hits.bam && \
touch .status.$modulename.sam2bam

## ONLY NEEDED FOR GTEx PROJECT (which has different chromosome names)
#[ ! -f .status.$modulename.rehead ] && \
#_header_change.sh && \
#touch .status.$modulename.rehead

[ ! -f .status.$modulename.bam2stat ] && \
echo `samtools view -cF 0x100 accepted_hits.bam` "primary alignments (from samtools view -cF 0x100)" > accepted_hits.bam.stat && \
samtools flagstat accepted_hits.bam >> accepted_hits.bam.stat && \
touch .status.$modulename.bam2stat

### bigwig for UCSC
echo "## generating bigwig files for UCSC display"

#bamToBed -i $samplename.accepted_hits.bam -bed12 | awk '{if($1!~/_/)print}' > $samplename.accepted_hits.bed ## Note: may take more time in converting bam to sam
[ ! -f .status.$modulename.sam2bw ] && \
sam2bed -v bed12=T -v sCol=NH accepted_hits.sam | awk '{if($1!~/_/)print}' > accepted_hits.bed && \
sort -k1,1 accepted_hits.bed | bedItemOverlapCount $index -bed12 -chromSize=$ANNOTATION/ChromInfo.txt stdin | sort -k1,1 -k2,2n | sed 's/ /\t/g'> accepted_hits.bedGraph && \
bedGraphToBigWig accepted_hits.bedGraph $ANNOTATION/ChromInfo.txt accepted_hits.bw && \
touch .status.$modulename.sam2bw 

# normalized bigwig (rpm)
[ ! -f .status.$modulename.sam2normalizedbw ] && \
#total_mapped_reads=`cat logs/bowtie.*t_kept_reads.log | grep -P "1\stime" | awk '{s=$1+s;}END{print s}'` && 
total_mapped_reads=`samtools view -cF 0x100 accepted_hits.bam` && \
echo "total_mapped_reads:$total_mapped_reads" && \
awk -v tmr=$total_mapped_reads 'BEGIN{OFS="\t"; print "# total_mapped_reads="tmr;}{$4=$4*1e6/tmr; print}' accepted_hits.bedGraph > accepted_hits.normalized.bedGraph && \
bedGraphToBigWig accepted_hits.normalized.bedGraph $ANNOTATION/ChromInfo.txt accepted_hits.normalized.bw && \
touch .status.$modulename.sam2normalizedbw

# % of genome coverage vs. RNAseq density (e.g. >1rpm)
[ ! -f .status.$modulename.rpm_vs_coverage ] && \
awk 'BEGIN{max=100; UNIT=0.01; OFS="\t";}{if($0~/^#/) {print; next;} i=int($4/UNIT);if(i>max) i=max; rpm[i]+=($3-$2);}END{for(x=max;x>=0;x--) print x*UNIT, rpm[x]?rpm[x]:0;}' accepted_hits.normalized.bedGraph > accepted_hits.normalized.rpm_vs_coverage.txt && \
touch .status.$modulename.rpm_vs_coverage

#rm accepted_hits.bed accepted_hits.*bedGraph

###########################################
echo "["`date`"] STEP 6. call variation [OFF]"
###########################################

cd $outputdir/$samplename

[ ! -f .status.$modulename.callSNP ] && \
_callSNP.sh accepted_hits.sam && \
touch .status.$modulename.callSNP

### shuilin's GATK
##[ ! -f .status.$modulename.callSNP_GATK ] && \
##_bam2vcf.sh accepted_hits.sam && \
##touch .status.$modulename.callSNP_GATK

###########################################
echo "["`date`"] STEP 7. assembly and quantification"
###########################################

cd $outputdir/$samplename

#echo "## run cufflinks to assembly (including do de-novo discovery)" [PAUSED becaused of memory issue]
#[ ! -f .status.$modulename.cufflinks.denovo ] && \
#cufflinks --no-update-check $strandoption -o ./denovo -p $CPU -g $ANNOTATION_GTF -M $MASK_GTF accepted_hits.bam 2> cufflinks.denovo.log && \
#touch .status.$modulename.cufflinks.denovo

##echo "## run trinity to do de-novo discovery"
#Trinity.pl --output denovo --seqType fq --JM 100G --left $R1 --right $R2 --CPU $CPU

#echo "## run Scripture to do de-novo discovery" [TURN OFF due to the possible memory leak]
## see demo at: http://garberlab.umassmed.edu/data/RNASeqCourse/analysis.workshop.pdf
## "Scripture initially transforms the genome into a graph topology, which represents all possible connections of bases in the transcriptome either when they occur consecutively or when they are connected by a spliced read. Scripture uses this graph topology to reduce the transcript reconstruction problem to a statistical segmentation problem of identifying significant transcript paths across the graph" (http://www.nature.com.ezp-prod1.hul.harvard.edu/nmeth/journal/v8/n6/full/nmeth.1613.html)
#[ ! -f .status.$modulename.scripture ] && \
#> .scripture.paraFile && \
#for i in `seq 1 22` X Y M; do echo "java -Xmx40000m -jar $pipeline_path/bin/scripture-beta2.jar -alignment accepted_hits.bam -out scripture.segments.$i -sizeFile $GENOME/Sequence/WholeGenomeFasta/hg19.chrom.size -chr chr$i -chrSequence $GENOME/Sequence/Chromosomes/chr$i.fa &>>scripture.log" >> .scripture.paraFile; done && \
#rm -f .scripture.paraFile.completed && \
#ParaFly -c .scripture.paraFile -CPU 8 && \
#touch .status.$modulename.scripture

echo "## run cufflinks to get FPKM"
# Using gtf from deno assembly
# Note: "-b" option (for bias correction) can lead to segementation fault error.
[ ! -f .status.$modulename.cufflinks ] && \
cufflinks --no-update-check $strandoption -o ./ -p $CPU -G $ANNOTATION_GTF -M $MASK_GTF --compatible-hits-norm --multi-read-correct accepted_hits.bam && \
touch .status.$modulename.cufflinks 

#echo "## run cufflinks without -M option"
#cufflinks -q --no-update-check $strandoption -o ./cufflink_wo_M -p $CPU -G $ANNOTATION_GTF -b $BOWTIE_INDEXES/genome.fa --multi-read-correct accepted_hits.bam

echo "## run htseq for reads count"
[ ! -f .status.$modulename.htseqcount ] && \
htseq-count -m intersection-strict -t exon -i gene_id -s no -q accepted_hits.sam $ANNOTATION_GTF > hgseqcount.by.gene.tab 2> hgseqcount.by.gene.tab.stderr && \
touch .status.$modulename.htseqcount

############################################
echo "["`date`"] STEP 8. for uniq"
############################################

## extract the unique mapper only
[ -d $outputdir/$samplename/uniq ] || mkdir $outputdir/$samplename/uniq
cd $outputdir/$samplename/uniq

[ ! -f $outputdir/$samplename/.status.$modulename.uniq ] && \
samtools view -SH $outputdir/$samplename/accepted_hits.sam > accepted_hits.sam && \
fgrep -w NH:i:1 $outputdir/$samplename/accepted_hits.sam >> accepted_hits.sam && \
samtools view -Sbut $BOWTIE2_INDEXES/genome.fai accepted_hits.sam | samtools sort - accepted_hits.sorted && \
mv accepted_hits.sorted.bam accepted_hits.bam && \
samtools index accepted_hits.bam && \
cufflinks --no-update-check $strandoption -o ./ -p $CPU -G $ANNOTATION_GTF -M $MASK_GTF --compatible-hits-norm accepted_hits.bam && \
sam2bed -v bed12=T accepted_hits.sam | awk '{if($1!~/_/)print}' > accepted_hits.bed && \
sort -k1,1 accepted_hits.bed | bedItemOverlapCount $index -bed12 -chromSize=$ANNOTATION/ChromInfo.txt stdin | sort -k1,1 -k2,2n | sed 's/ /\t/g' > accepted_hits.bedGraph && \
bedGraphToBigWig accepted_hits.bedGraph $ANNOTATION/ChromInfo.txt accepted_hits.bw && \
total_mapped_reads=`wc -l accepted_hits.bed | cut -f1 -d' '` && \
echo "total_mapped_reads:$total_mapped_reads" && \
awk -v tmr=$total_mapped_reads 'BEGIN{OFS="\t"; print "# total_mapped_reads="tmr;}{$4=$4*1e6/tmr; print}' accepted_hits.bedGraph > accepted_hits.normalized.bedGraph && \
bedGraphToBigWig accepted_hits.normalized.bedGraph $ANNOTATION/ChromInfo.txt accepted_hits.normalized.bw && \
touch $outputdir/$samplename/.status.$modulename.uniq

#[ ! -f $outputdir/$samplename/.status.$modulename.uniq.bam2annotation ] && \
#_bam2annotation.sh accepted_hits.bam > accepted_hits.bam.bam2annotation && \
#_bam2annotation.r accepted_hits.bam.bam2annotation accepted_hits.bam.bam2annotation.pdf && \
#touch $outputdir/$samplename/.status.$modulename.uniq.bam2annotation

[ ! -f $outputdir/$samplename/.status.$modulename.uniq.bam2stat ] && \
echo `samtools view -cF 0x100 accepted_hits.bam` "primary alignments (from samtools view -cF 0x100)" > accepted_hits.bam.stat && \
samtools flagstat accepted_hits.bam >> accepted_hits.bam.stat && \
touch $outputdir/$samplename/.status.$modulename.uniq.bam2stat

#echo "## run cufflinks to assembly (including do de-novo discovery)"  #[PAUSED becaused of memory issue]
#[ ! -f $outputdir/$samplename/.status.$modulename.uniq.cufflinks.denovo ] && \
#cufflinks --no-update-check $strandoption -o ./denovo -p $CPU -g $ANNOTATION_GTF accepted_hits.bam.non-rRNA-mt.bam 2> cufflinks.denovo.log && \
#touch $outputdir/$samplename/.status.$modulename.uniq.cufflinks.denovo

echo "## normalizing: instead of using total reads, use reads only mapped to non-rRNA-mtRNA for normalization"
[ ! -f $outputdir/$samplename/.status.$modulename.uniq.normalize ] && \
total_mapped_reads2=`grep total_non-rRNA-mt accepted_hits.bam.bam2annotation | cut -f2 -d' '` && \
awk -v tmr=$total_mapped_reads2 'BEGIN{OFS="\t"; print "# total-rRNA-chrM="tmr;}{$4=$4*1e6/tmr; print}' accepted_hits.bedGraph > accepted_hits.normalized2.bedGraph && \
bedGraphToBigWig accepted_hits.normalized2.bedGraph $ANNOTATION/ChromInfo.txt accepted_hits.normalized2.bw && \
touch $outputdir/$samplename/.status.$modulename.uniq.normalize

echo "## calcualte RPKM (based on TOTAL reads mapped to nuclear genome)"
[ ! -f $outputdir/$samplename/.status.$modulename.uniq.cufflinks.rpkm ] && \
cufflinks --no-update-check $strandoption -o ./rpkm -p $CPU -G $ANNOTATION_GTF accepted_hits.bam.non-rRNA-mt.bam 2> cufflinks.rpkm.log && \
touch $outputdir/$samplename/.status.$modulename.uniq.cufflinks.rpkm

[ ! -f $outputdir/$samplename/.status.$modulename.uniq.htseqcount ] && \
htseq-count -m intersection-strict -t exon -i gene_id -s no -q accepted_hits.sam $ANNOTATION_GTF > hgseqcount.by.gene.tab 2> hgseqcount.by.gene.tab.stderr && \
touch $outputdir/$samplename/.status.$modulename.uniq.htseqcount

[ ! -f $outputdir/$samplename/.status.$modulename.uniq.callSNP ] && \
_callSNP.sh accepted_hits.sam && \
touch $outputdir/$samplename/.status.$modulename.uniq.callSNP

## shuilin's GATK
#[ ! -f $outputdir/$samplename/.status.$modulename.uniq.callSNP_GATK ] && \
#samtools view -SH $outputdir/$samplename/accepted_hits.sam > accepted_hits.sam && \
#fgrep -w NH:i:1 $outputdir/$samplename/accepted_hits.sam >> accepted_hits.sam && \
#_bam2vcf.sh accepted_hits.sam && \
#touch $outputdir/$samplename/.status.$modulename.uniq.callSNP_GATK

[ ! -f $outputdir/$samplename/.status.$modulename.uniq.rpm_vs_coverage ] && \
awk 'BEGIN{max=100; UNIT=0.01; OFS="\t";}{if($0~/^#/) {print; next;} i=int($4/UNIT);if(i>max) i=max; rpm[i]+=($3-$2);}END{for(x=max;x>=0;x--) print x*UNIT, rpm[x]?rpm[x]:0;}' accepted_hits.normalized.bedGraph > accepted_hits.normalized.rpm_vs_coverage.txt && \
touch $outputdir/$samplename/.status.$modulename.uniq.rpm_vs_coverage

#rm accepted_hits.bed accepted_hits.*bedGraph

############################################
echo "["`date`"] STEP 9. prepare for tracks files to display on UCSC / IGV"
############################################
#
[ -d $inputdir/../for_display ] || mkdir $inputdir/../for_display
cd $inputdir/../for_display

### others
[ ! -f $outputdir/$samplename/.status.$modulename.makelinks ] && \
# make soft link
# multi
ln -fs $outputdir/$samplename/accepted_hits.bam $samplename.multi.accepted_hits.bam && \
ln -fs $outputdir/$samplename/accepted_hits.bam.bai $samplename.multi.accepted_hits.bam.bai && \
ln -fs $outputdir/$samplename/isoforms.fpkm_tracking $samplename.multi.isoforms.fpkm_tracking && \
ln -fs $outputdir/$samplename/genes.fpkm_tracking $samplename.multi.genes.fpkm_tracking && \
ln -fs $outputdir/$samplename/hgseqcount.by.gene.tab $samplename.multi.hgseqcount.by.gene.tab && \
ln -fs $outputdir/$samplename/accepted_hits.bw $samplename.multi.accepted_hits.bw && \
ln -fs $outputdir/$samplename/accepted_hits.normalized.bw $samplename.multi.accepted_hits.normalized.bw && \
# uniq
ln -fs $outputdir/$samplename/uniq/accepted_hits.bam $samplename.uniq.accepted_hits.bam && \
ln -fs $outputdir/$samplename/uniq/accepted_hits.bam.bai $samplename.uniq.accepted_hits.bam.bai && \
ln -fs $outputdir/$samplename/uniq/isoforms.fpkm_tracking $samplename.uniq.isoforms.fpkm_tracking && \
ln -fs $outputdir/$samplename/uniq/genes.fpkm_tracking $samplename.uniq.genes.fpkm_tracking && \
ln -fs $outputdir/$samplename/uniq/hgseqcount.by.gene.tab $samplename.uniq.hgseqcount.by.gene.tab && \
ln -fs $outputdir/$samplename/uniq/accepted_hits.bw $samplename.uniq.accepted_hits.bw && \
ln -fs $outputdir/$samplename/uniq/accepted_hits.normalized.bw $samplename.uniq.accepted_hits.normalized.bw && \
ln -fs $outputdir/$samplename/uniq/accepted_hits.normalized2.bw $samplename.uniq.accepted_hits.normalized2.bw && \
# gtf of assembly
echo "track name=$samplename.multi.gtf description=$samplename.multi.gtf visibility=pack colorByStrand='200,100,0 0,100,200'" > $samplename.multi.transcripts.gtf && \
cat $outputdir/$samplename/transcripts.gtf >> $samplename.multi.transcripts.gtf && \
gzip -f $samplename.multi.transcripts.gtf && \
# for uniq
echo "track name=$samplename.uniq.gtf description=$samplename.uniq.gtf visibility=pack colorByStrand='200,100,0 0,100,200'" > $samplename.uniq.transcripts.gtf && \
cat $outputdir/$samplename/uniq/transcripts.gtf >> $samplename.uniq.transcripts.gtf && \
gzip -f $samplename.uniq.transcripts.gtf && \
## QC
ln -fs $outputdir/$samplename/$samplename.R1_fastqc $samplename.R1_fastqc && \
ln -fs $outputdir/$samplename/$samplename.R2_fastqc $samplename.R2_fastqc && \

touch $outputdir/$samplename/.status.$modulename.makelinks

echo "["`date`"] DONE: $modulename job for sample $samplename is done !!"