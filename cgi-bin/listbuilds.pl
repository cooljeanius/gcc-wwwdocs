#! /usr/bin/perl -s
# -*- perl -*-

# This is where the data is found.
$htdocs = '/www/gcc/htdocs';
$root = 'glibc/builds';

chdir "$htdocs/$root" || die "cannot change to $htdocs/$root";

# Further distinguashions are made based on OS, architecture, and date.
# Find all the OS names now.
@oses = ();
while (<*>) {
  push @oses, $_;
}

# Now read for all OSes the architectures.
for ($i = 0; $i <= $#oses; ++$i) {
  local($os) = $oses[$i];
  @{$os} = ();
  while (<$os/*>) {
    push @{$os}, $_;
  }
}

# Now read about the builds.
for ($i = 0; $i <= $#oses; ++$i) {
  local($os) = $oses[$i];
  local($narchs) = $#{$os};
  for ($j = 0; $j <= $narchs; ++$j) {
    local($osarch) = ${$os}[$j];
    @{$osarch} = ();
    while (<$osarch/*>) {
      push @{$osarch}, $_;
    }
  }
}

# Create the table.
printf "Content-type: text/html\n\n";
printf "<html><head><title>glibc build report</title></head><body>\n";
printf "<h1>GNU libc build reports</h1>\n";
printf "The following table contains informations about the builds of ";
printf "GNU libc on various platforms.  The links in the table bring you ";
printf "to the index for the appropriate build.  From this point you can ";
printf "select whether to look at the error or warning messages or at the ";
printf "results for a specific subdirectory.<p>\n";
printf "<center><table border=\"1\">\n";
printf "<tr><th width=\"80\">OS</th><th width=\"60\">Architecture</th>";
printf "<th width=\"80\">Date</th></tr>\n";

for ($i = 0; $i <= $#oses; ++$i) {
  local($os) = $oses[$i];
  local($narchs) = $#{$os};

  # First find out how many totals builds are there.
  local($n) = 0;
  for ($j = 0; $j <= $narchs; ++$j) {
    local($osarch) = $$os[$j];
    local($nn);
    if ($#{$osarch} < 0) {
      $nn = 1;	# We have no build, just print the architecture name.
    } else {
      $nn = 1 + $#{$osarch};
    }
    $count{"$osarch"} = $nn;
    $n += $nn;
  }

  printf "<tr><td rowspan=\"%d\">%s", $n, $os;

  for ($j = 0; $j <= $narchs; ++$j) {
    local($arch);
    ($arch = $$os[$j]) =~ s/^.*\/([^\/]+)$/\1/;
    printf '<tr>' if ($j > 0);
    printf "<td rowspan=\"%s\">%s", $count{"$$os[$j]"}, $arch;

    for ($m = 0; $m <= $#{$$os[$j]}; ++$m) {
      printf '<tr>' if ($m > 0);
      local($date);
      ($date = ${$$os[$j]}[$m]) =~ s/^.*\/([^\/]+)$/\1/;
      printf "<td align=center><a href=\"/%s/%s/index.html\">%s</a></tr>\n", $root, ${$$os[$j]}[$m], $date;
    }
  }
}

printf "</table></center></body>\n";
