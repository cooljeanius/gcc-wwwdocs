#!/usr/bin/perl -s
#
# cvsweb - a CGI interface to the CVS tree.
#
# Written by Bill Fenner <fenner@parc.xerox.com> on his own time.
# Insert BSD copyright here.
#
#HTTP_USER_AGENT: Mozilla/1.1N (X11; I; SunOS 4.1.3_U1 sun4m) via proxy gateway CERN-HTTPD/3.0 libwww/2.17
#SERVER_NAME: www.freebsd.org
#QUERY_STRING: baz
#SCRIPT_FILENAME: /usr/local/www/cgi-bin/env.pl
#SERVER_PORT: 80
#HTTP_ACCEPT: */*, image/gif, image/x-xbitmap, image/jpeg
#SERVER_PROTOCOL: HTTP/1.0
#HTTP_COOKIE: s=beta26429821397802167
#PATH_INFO: /foo/bar
#REMOTE_ADDR: 13.1.64.94
#DOCUMENT_ROOT: /usr/local/www/data/
#PATH: /sbin:/bin:/usr/sbin:/usr/bin
#PATH_TRANSLATED: /usr/local/www/data//foo/bar
#GATEWAY_INTERFACE: CGI/1.1
#REQUEST_METHOD: GET
#SCRIPT_NAME: /cgi-bin/env.pl
#SERVER_SOFTWARE: Apache/1.0.0
#REMOTE_HOST: beta.xerox.com
#SERVER_ADMIN: webmaster@freebsd.org
#
use Time::Local;

##### Start of Configuration Area ########

## files
# mapping to mimetypes
$mime_types='/www/conf/mime.types';
# further configuration
$config = '/www/egcs/cvsweb';

$hsty_base = "";
require 'cgi-style.pl';
#&get_the_source;

%CVSROOT = (
	    'egcs', '/cvs/egcs',
	    'bindev', '/cvs/bindev',
            'glibc', '/cvs/glibc',
            'guile', '/cvs/guile',
	    );

$cvstreedefault = 'sourceware';
$cvstree = $cvstreedefault;
$cvsroot = $CVSROOT{"$cvstree"} || "/cvs/egcs";


$intro = "
This is a WWW interface to CVS repositories on the 
<a href=\"http://egcs.cygnus.com/\"><code>egcs.cygnus.com</code></a> 
web site.  You can browse the file hierarchy by picking directories
(which have slashes after them, e.g. <b>src/</b>).
If you pick a file, you will see the revision history for that file.
Selecting a revision number will download that revision of the file.
There is a link at each revision to display diffs between that revision
and the previous one, and a form at the bottom of the page that allows
you to display diffs between arbitrary revisions.
<p>
If you would like to use this CGI script on your own web server and
CVS tree, see <A HREF=\"http://www.freebsd.org/~fenner/cvsweb/\">
the CVSWeb distribution site</A>.
<p>
Please send any suggestions, comments, etc. to
<A HREF=\"mailto:fenner\@freebsd.org\">Bill Fenner &lt;fenner\@freebsd.org&gt;</A>
";
$shortinstr = "
Click on a directory to enter that directory. Click on a file to display
its revision history and to get a
chance to display diffs between revisions. 
";


############## Human Readable Diff stuff
# (c) 1998 H. Zeller <zeller@think.de>
#
# Generates two columns of color encoded
# diff; much like xdiff or emacs-ediff mode.
# This diff-stuff is a piece of code I once made for
# cvs2html which is under GPL,
# see http://sslug.imm.dtu.dk/cvs2html/
# (c) 1997/98 Peter Toft <pto@sslug.imm.dtu.dk>
# do not blame him, if this doesn't work; it's my fault :-)
#
# some parameters to screw:
##

# use human-readable diff as default; otherwise
# the normal unidiff does this.
# if this is disabled, you get two links
# '->Diffs to 1.1 ->(nice version)'
$hr_default=0;

# make lines breakable so that the columns do not
# exceed the width of the browser
$hr_breakable=0;

# give out function names in human readable diffs
# this just makes sense if we have C-files, otherwise
# diff's heuristic doesn't work well ..
# ( '-p' option to diff)
$hr_funout=0;

# ignore whitespaces for human readable diffs
# (indendation and stuff ..)
# ( '-w' option to diff)
$hr_ignwhite=1;

# ignore diffs which are caused by
# keyword-substitution like $Id - Stuff
# ( '-kk' option to rcsdiff)
$hr_ignkeysubst=1;

# Default background color for the diffs
$backcolor = "#EEEEEE";

# Colors and font to show the diff type of code changes
$diffcolorHeading='#99CCCC';  # color of 'Line'-heading of each diffed file
$diffcolorEmpty  ='#CCCCCC';  # color of 'empty' lines
$diffcolorRemove ='#FF9999';  # Removed line(s) (left)  (  -  )
$diffcolorChange ='#99FF99';  # Changed line(s) (     both    )
$diffcolorAdd    ='#CCCCFF';  # Added line(s)   (  - )  (right)
$diffcolorDarkChange ='#99CC99';  # lines, which are empty in change
$difffontface    ="Helvetica,Arial";
$difffontsize    ="-1";

### END diff stuff

# used icons; if icon-url is empty, the text representation is used; if
# you do not want to have an ugly tooltip for the icon, remove the
# text-representation.
# The width and height of the icon allow the browser to correcly display
# the table while still loading the icons.
# format:               TEXT      ICON-URL          width height
%ICONS  = (
	   back => [ ("[BACK]", "/icons/back.gif", 20,   22) ],
	   dir  => [ ("[DIR]",  "/icons/dir.gif",  20,   22) ],
	   file => [ ("[TXT]",  "/icons/text.gif", 20,   22) ],
	   );

# the width of the textinput of the
# request-diff-form
$inputTextSize = 12;

# the length to which the last logentry should
# be truncated when shown in the directory view
$shortLogLen = 80;

# Show directory as table
# this is much more readable but has one
# drawback: the whole table has to be loaded
# before common browsers display it which may
# be annoying if you have a slow link - and a
# large directory ..
$dirtable=1;
# show different colors for even/odd rows
@tabcolors=('#EEEEEE', '#FFFFFF');
$tablepadding=2;

# remember to set the path to your
# rcsutils: co, rlog, rcsdiff
#$ENV{'PATH'}='/usr/local/bin'

# quick mime-type lookup; maps file-suffices to
# mime-types for displaying checkouts in the browser.
# Further MimeTypes will be found in the 
# file $mime_types (apache style mime.types - file)
# - add common mappings here for faster lookup
%MTYPES = (
	   "html"  => "text/html",
	   "shtml" => "text/html",
	   "gif"   => "image/gif",
	   "jpeg"  => "image/jpeg",
	   "jpg"   => "image/jpep",	   
	   );

#
# Defaults for startup
#
%DEFAULTSWITCH = (
		  "sortbydate" => "0",
		  "hideattic"  => "1",
		  );

##### End of Configuration Area ########

$verbose = $v;
$checkoutMagic = "~checkout~";
($where = $ENV{'PATH_INFO'}) =~ s|^/($checkoutMagic)?||;
$doCheckout = ($ENV{'PATH_INFO'} =~ /^\/$checkoutMagic/);
$where =~ s|/$||;
($scriptname = $ENV{'SCRIPT_NAME'}) =~ s|^/?|/|;
$scriptname =~ s|/$||;
$scriptwhere = $scriptname . '/' . $where;
$scriptwhere =~ s|/$||;

# in lynx, it it very annoying to have two links
# per file, so disable the link at the icon
# in this case:
($Browser = $ENV{'HTTP_USER_AGENT'}) =~ s|/.*$||;
$nofilelinks=($Browser eq 'Lynx');

# put here the variables we need in order
# to hold our state - they will be added (with
# their current value) to any link/query string 
# you construct
@usedvars=('cvsroot','hideattic','sortbydate');

if ($query = $ENV{'QUERY_STRING'}) {
    foreach (split(/&/, $query)) {
	s/%(..)/sprintf("%c", hex($1))/ge;	# unquote %-quoted
	if (/(\S+)=(.*)/) {
	    $input{$1} = $2;
	} else {
	    $input{$_}++;
	}
    }
}
    
# get actual parameters
$bydate=$input{"sortbydate"};

$barequery = "";
foreach (@usedvars) {
    if (defined $DEFAULTSWITCH{$_} && not defined $input{$_}) {
	if (not defined $input{"copt"}) {
	    # 'copt' isn't defined -> not the result of empty input checkbox -> set default
	    $input{$_} = $DEFAULTSWITCH{$_};
	} else {
	    $input{$_} = 0;
	}
    }
    
    if (defined $input{$_}) {
	if ($barequery) {
	    $barequery = $barequery . "&";
	}
	# in case of cvsroot: snip from original query-string to avoid quoting again
	if ($_ eq $cvsroot) {
	    ($thisval = $query) =~ s/^.*($_=[^&]*).*$/$1/;
	} else {
	    # pure numeric value
	    $thisval = "$_=" . $input{$_};
	}
	$barequery = $barequery  . $thisval;
    }
}
$query = "?$barequery";
if ($barequery) {
    $barequery = "&" . $barequery;
}


do "$config" if -f $config;

if ($input{'cvsroot'}) {
    if ($CVSROOT{$input{'cvsroot'}}) {
	$cvstree = $input{'cvsroot'};
	$cvsroot = $CVSROOT{"$cvstree"};
    }
}

# create icons out of description
foreach $k (keys %ICONS) {
    ($itxt,$ipath,$iwidth,$iheight)=@{$ICONS{$k}};
    if ($ipath) {
	$ {"${k}icon"} = "<IMG SRC=\"$ipath\" ALT=\"$itxt\" BORDER=\"0\" WIDTH=\"$iwidth\" HEIGHT=\"$iheight\">";
    } else {
	$ {"${k}icon"} = $itxt;
    }
}

do "$config-$cvstree" if -f "$config-$cvstree";

$fullname = $cvsroot . '/' . $where;

if (!-d $cvsroot) {
    &fatal("500 Internal Error",'$CVSROOT not found!<P>The server on which the CVS tree lives is probably down.  Please try again in a few minutes.');
}


if (-d $fullname) {
	opendir(DIR, $fullname) || &fatal("404 Not Found","$where: $!");
	@dir = readdir(DIR);
	closedir(DIR);
	if ($where eq '') {
	    print &html_header("Sourceware.cygnus.com CVS Repository");
	    print $intro;
	} else {
	    print &html_header("/$where");
	    print $shortinstr;
	}
	
	getDirLogs($fullname);
	
	# give direct access to dirs
	print "<p>Current directory: <b>", &clickablePath($where,0), "</b>\n";
	
	print "<P><HR NOSHADE>\n";
	# Using <MENU> in this manner violates the HTML2.0 spec but
	# provides the results that I want in most browsers.  Another
	# case of layout spooging up HTML.
	
	if ($dirtable) {
	    print "<table  width=\"100%\" border=0 cellspacing=0 cellpadding=$tablepadding >";
	    print "<tr><th align=left>File</th>";
	    # do not display the other column-headers, if we do not have any files
	    # with revision information:
	    print "<th align=left>Rev.</th><th align=left>Age</th><th align=left>last Logentry</th>" 
		if scalar(%fileinfo);
	    print "</tr>";
	} else {
	    print "<menu>\n";
	}
	$dirrow = 0;
	
	lookingforattic:
	for ($i = 0; $i <= $#dir; $i++) {
		if ($dir[$i] eq "Attic") {
		    last lookingforattic;
		}
	}
	$haveattic = 1 if ($i <= $#dir);
	if (!$input{'hideattic'} && ($i <= $#dir) &&	opendir(DIR, $fullname . "/Attic")) {
	    splice(@dir, $i, 1,
			grep((s|^|Attic/|,!m|/\.|), readdir(DIR)));
		closedir(DIR);
	}
	# Sort without the Attic/ pathname.
	# place directories first
	foreach (sort { &fileSortCmp } @dir) {
	    if ($_ eq '.') {
		next;
	    }
	    if (s|^Attic/||) {
		$attic = " (in the Attic)";
	    } else {
		$attic = "";
	    }
	    
	    if ($_ eq '..') {
		next if ($where eq '');
		print "<tr bgcolor=\"" . @tabcolors[$dirrow%2] . "\"><td>" if ($dirtable);
		($updir = $scriptwhere) =~ s|[^/]+$||;
		$url = $updir . $query;
		if ($nofilelinks) {
		    print $backicon;
		} else {
		    print &link($backicon,$url);
		}
		print " ", &link("Previous Directory",$url);
		print (($dirtable) ? "</td><td colspan=3>&nbsp;</td></tr>" : "<br>");
#		print "<IMG SRC=???> ",
#		    &link("Directory-wide diffs", $scriptwhere . '/*'), "<BR>";
		$dirrow++;
	    } elsif (-d $fullname . "/" . $_) {
		print "<tr bgcolor=\"" . @tabcolors[$dirrow%2] . "\"><td>" if ($dirtable);
		$url = $scriptwhere . '/' . $_ . '/' . $query;
		print "<A NAME=\"$_\">";
		if ($nofilelinks) {
		    print $diricon;
		} else {
		    print &link($diricon,$url);
		}
		print " ", &link($_ . "/", $url), $attic;
		print (($dirtable) ? "</td><td colspan=3>&nbsp;</td></tr>" : "<br>");
		$dirrow++;
	    } elsif (s/,v$//) {
		print "<tr bgcolor=\"" . @tabcolors[$dirrow%2] . "\"><td>" if ($dirtable);
		print "<A NAME=\"$_\">";
# TODO: add date/time?  How about sorting? .. done (hen)
		$url = $scriptwhere . '/' . ($attic ? "Attic/" : "") . $_ . $query;
		$head='';$date='';$log='';
		($head,$date,$log)=@{$fileinfo{$_}};
		if ($nofilelinks) {
		    print $fileicon;
		} else {
		    print &link($fileicon,$url);
		}
		print " ", &link($_, $url), $attic;
		print "</td><td>&nbsp;" if ($dirtable);
		print " <b>$head</b>";
		print "</td><td>&nbsp;" if ($dirtable);
		if ($date) {
		    print " <i>" . readableTime(timegm(localtime(time())) - $date,0) . "</i>";
		}
		print "</td><td>&nbsp;" if ($dirtable);
		if ($log) {
		    ($nospacelog=$log)=~s/\s+/ /;
		    print " <font size=-1>" . &htmlify(substr($log,0,$shortLogLen));
		    if (length $log > 80) {
			print "...";
		    }
		    print "</font>";
		}
		print "</td>" if ($dirtable);
		print (($dirtable) ? "</tr>" : "<br>");
		$dirrow++;
	    }
	    print "\n";
	}
	print (($dirtable) ? "</table>" : "</menu>") . "\n";
	
	if ($input{"only_on_branch"}) {
	    print "<HR><FORM METHOD=\"GET\" ACTION=\"${scriptwhere}\">\n";
	    print "Currently showing only branch $input{'only_on_branch'}.\n";
	    $input{"only_on_branch"}="";
	    foreach $k (keys %input) {
		print "<INPUT TYPE=hidden NAME=$k VALUE=$input{$k}>\n" if $input{$k};
	    }
	    print "<INPUT TYPE=SUBMIT VALUE=\"Show all branches\">\n";
	    print "</FORM>\n";
	}
	$formwhere = $scriptwhere;
	$formwhere =~ s|Attic/?$|| if ($input{'hideattic'});
	
	print "<hr><FORM METHOD=\"GET\" ACTION=\"${formwhere}\">\n";
	print "<table>";
	print "<tr><td><input type=\"CHECKBOX\" value=\"1\" name=\"sortbydate\" ";
	print ($input{"sortbydate"} ? "CHECKED>" : ">&nbsp;");
	print "Sort by Age</td><td>";
	print "<INPUT TYPE=HIDDEN NAME=\"copt\" VALUE=\"X\">\n";
	print "<input type=\"CHECKBOX\" value=\"1\" name=\"hideattic\" ";
	print ($input{'hideattic'} ? "CHECKED>" : ">&nbsp;");
	print "Hide attic files</td><td>";
	print "<input type=submit value=\"Change Options\"></td></tr>";
	print "</table>";
	print "<INPUT TYPE=HIDDEN NAME=\"cvsroot\" VALUE=\"$cvstree\">\n"
	    if &cvsroot;
	print "</FORM>\n";
	
	print &html_footer;
	print "</BODY></HTML>\n";
    } elsif (-f $fullname . ',v') {
	if ($input{'rev'} =~ /^[\d\.]+$/ || $doCheckout) {
	    &checkout($fullname, $input{'rev'});
	    exit;
	}
	if ($input{'r1'} && $input{'r2'}) {
	    &dodiff($fullname, $input{'r1'}, $input{'tr1'},
		    $input{'r2'}, $input{'tr2'}, $input{'f'});
	    exit;
	}
	print("going to dolog($fullname)\n") if ($verbose);
	&dolog($fullname);
    } elsif ($fullname =~ s/\.diff$// && -f $fullname . ",v" &&
	     $input{'r1'} && $input{'r2'}) {
	# Allow diffs using the ".diff" extension
	# so that browsers that default to the URL
	# for a save filename don't save diff's as
	# e.g. foo.c
	&dodiff($fullname, $input{'r1'}, $input{'tr1'},
		$input{'r2'}, $input{'tr2'}, $input{'f'});
	exit;
    } elsif (($newname = $fullname) =~ s|/([^/]+)$|/Attic/$1| &&
	     -f $newname . ",v") {
	# The file has been removed and is in the Attic.
	# Send a redirect pointing to the file in the Attic.
	($newplace = $scriptwhere) =~ s|/([^/]+)$|/Attic/$1|;
	&redirect($newplace);
	exit;
    } elsif (0 && (@files = &safeglob($fullname . ",v"))) {
	print "Content-type: text/plain\n\n";
	print "You matched the following files:\n";
	print join("\n", @files);
	# Find the tags from each file
	# Display a form offering diffs between said tags
    } else {
	# Assume it's a module name with a potential path following it.
	$xtra = $& if (($module = $where) =~ s|/.*||);
	# Is there an indexed version of modules?
	if (open(MODULES, "$cvsroot/CVSROOT/modules")) {
	    while (<MODULES>) {
		if (/^(\S+)\s+(\S+)/o && $module eq $1
		    && -d "${cvsroot}/$2" && $module ne $2) {
		    &redirect($scriptname . '/' . $2 . $xtra);
		}
	    }
	}
	&fatal("404 Not Found","$where: no such file or directory");
    }

sub htmlify {
	local($string, $pr) = @_;

	$string =~ s/&/&amp;/g;
	$string =~ s/\"/&quot;/g; 
	$string =~ s/</&lt;/g;
	$string =~ s/>/&gt;/g;

	# get URL's as link ..
	$string =~ s�(http|ftp)(://\S+)�<A HREF="$1$2">$1$2</A>�;

# ??	if ($pr) { 
#		$string =~ s|\bpr(\W+[a-z]+/\W*)(\d+)|<A HREF=/cgi/query-pr.cgi?pr=$2>$&</A>|ig;
#	}

	$string;
}

sub link {
	local($name, $where) = @_;

	"<A HREF=\"$where\">$name</A>\n";
}

sub revcmp {
	local($rev1, $rev2) = @_;
	local(@r1) = split(/\./, $rev1);
	local(@r2) = split(/\./, $rev2);
	local($a,$b);

	while (($a = shift(@r1)) && ($b = shift(@r2))) {
	    if ($a != $b) {
		return $a <=> $b;
	    }
	}
	if (@r1) { return 1; }
	if (@r2) { return -1; }
	return 0;
}

sub fatal {
	local($errcode, $errmsg) = @_;
	print "Status: $errcode\n";
	print &html_header("Error");
#	print "Content-type: text/html\n";
#	print "\n";
#	print "<HTML><HEAD><TITLE>Error</TITLE></HEAD>\n";
#	print "<BODY>Error: $errmsg</BODY></HTML>\n";
	print "Error: $errmsg\n";
	print &html_footer;
	exit(1);
}

sub redirect {
	local($url) = @_;
	print "Status: 301 Moved\n";
	print "Location: $url\n";
	print &html_header("Moved");
#	print "Content-type: text/html\n";
#	print "\n";
#	print "<HTML><HEAD><TITLE>Moved</TITLE></HEAD>\n";
#	print "<BODY>This document is located <A HREF=$url>here</A>.</BODY></HTML>\n";
	print "This document is located <A HREF=$url>here</A>.\n";
	print &html_footer;
	exit(1);
}

sub safeglob {
	local($filename) = @_;
	local($dirname);
	local(@results);

	($dirname = $filename) =~ s|/[^/]+$||;
	$filename =~ s|.*/||;

	if (opendir(DIR, $dirname)) {
		$glob = $filename;
	#	transform filename from glob to regex.  Deal with:
	#	[, {, ?, * as glob chars
	#	make sure to escape all other regex chars
		$glob =~ s/([\.\(\)\|\+])/\\$1/g;
		$glob =~ s/\*/.*/g;
		$glob =~ s/\?/./g;
		$glob =~ s/{([^}]+)}/($t = $1) =~ s-,-|-g; "($t)"/eg;
		foreach (readdir(DIR)) {
			if (/^${glob}$/) {
				push(@results, $dirname . "/" .$_);
			}
		}
	}

	@results;
}

sub getMimeTypeFromSuffix {
    my ($fullname) = @_;
    local ($mimetype, $suffix);

    ($suffix = $fullname) =~ s/^.*\.([^.]*)$/\1/;
    $mimetype=$MTYPES{$suffix};
    
    if (!$mimetype && -f $mime_types) {
	# okey, this is something special - search the
	# mime.types database
	open (MIMETYPES, "<$mime_types");
	while (<MIMETYPES>) {
	    if ($_ =~ /^\s*(\S+\/\S+).*\b$suffix\b/) {
		$mimetype=$1;
		last;
	    }
	}
	close (MIMETYPES);
    }
    
# okey, didn't find anything useful ..
    if (!($mimetype =~ /\S\/\S/)) {
	$mimetype="text/plain";
    }
    return $mimetype;
}

sub checkout {
    local($fullname, $rev) = @_;

    open(RCS, "co -p$rev '$fullname' 2>&1 |") ||
	&fail("500 Internal Error", "Couldn't co: $!");
# /home/ncvs/src/sys/netinet/igmp.c,v  -->  standard output
# or
# /home/ncvs/src/sys/netinet/igmp.c,v  -->  stdout
# revision 1.1.1.2
    $_ = <RCS>;
    if (/^(\S+),v\s+-->\s+st(andar)?d ?out(put)?\s*$/o && $1 eq $fullname) {
	# As expected
    } else {
	&fatal("500 Internal Error",
	       "Unexpected output from co: $_");
    }
    $_ = <RCS>; # discard line - no revision check
    $| = 1;

# get mimetype
    if (defined $input{"content-type"} && ($input{"content-type"} =~ /\S\/\S/)) {
	$mimetype=$input{"content-type"}
    }
    else {
	$mimetype = &getMimeTypeFromSuffix($fullname);
    }
    print "Content-type: $mimetype\n\n";
    print <RCS>;
    close(RCS);
}

sub dodiff {
	local($fullname, $r1, $tr1, $r2, $tr2, $f) = @_;

	if ($r1 =~ /([^:]+)(:(.+))?/) {
	    $rev1 = $1;
	    $sym1 = $3;
	}
	if ($rev1 eq 'text') {
	    $rev1 = $tr1;
	}
	if ($r2 =~ /([^:]+)(:(.+))?/) {
	    $rev2 = $1;
	    $sym2 = $3;
	}
	if ($rev2 eq 'text') {
	    $rev2 = $tr2;
	}
	if (!($rev1 =~ /^[\d\.]+$/) || !($rev2 =~ /^[\d\.]+$/)) {
	    &fatal("404 Not Found",
		    "Malformed query \"$ENV{'QUERY_STRING'}\"");
	}
#
# rev1 and rev2 are now both numeric revisions.
# Thus we do a DWIM here and swap them if rev1 is after rev2.
# XXX should we warn about the fact that we do this?
	if (&revcmp($rev1,$rev2) > 0) {
	    ($tmp1, $tmp2) = ($rev1, $sym1);
	    ($rev1, $sym1) = ($rev2, $sym2);
	    ($rev2, $sym2) = ($tmp1, $tmp2);
	}
#
#	XXX Putting '-p' here is a personal preference
	$human_readable = 0;
	if ($f eq 'c') {
	    $difftype = '-p -c';
	    $diffname = "Context diff";
	} elsif ($f eq 's') {
	    $difftype = '--side-by-side --width=164';
	    $diffname = "Side by Side";
	} elsif ($f eq 'h') {
	    $difftype = '-u';
	    $human_readable = 1;
	} elsif ($f eq 'u') {
	    $difftype = '-p -u';
	    $diffname = "Unidiff";
	} else {
	    $human_readable = $hr_default;
	    $difftype = '-u';
	    $diffname = "Unidiff";
	}

	# apply special options
	if ($human_readable) {
	    if ($hr_funout) {
		$difftype = $difftype . ' -p';
	    }
	    if ($hr_ignwhite) {
		$difftype = $difftype . ' -w';
	    }
	    if ($hr_ignkeysubst) {
		$difftype = $difftype . ' -kk';
	    }
	    $diffname = "Human readable";
	}
	
# XXX should this just be text/plain
# or should it have an HTML header and then a <pre>
	open(RCSDIFF, "rcsdiff $difftype -r$rev1 -r$rev2 '$fullname' 2>&1 |") 
	    || &fail("500 Internal Error", "Couldn't rcsdiff: $!");
	if ($human_readable) {
	    print "Content-type: text/html\n\n";
	    &human_readable_diff($rev2);
	    exit;
	} else {
	    print "Content-type: text/plain\n\n";
	}
#
#===================================================================
#RCS file: /home/ncvs/src/sys/netinet/tcp_output.c,v
#retrieving revision 1.16
#retrieving revision 1.17
#diff -c -r1.16 -r1.17
#*** /home/ncvs/src/sys/netinet/tcp_output.c     1995/11/03 22:08:08     1.16
#--- /home/ncvs/src/sys/netinet/tcp_output.c     1995/12/05 17:46:35     1.17
#
# Ideas:
# - nuke the stderr output if it's what we expect it to be
# - Add "no differences found" if the diff command supplied no output.
#
#*** src/sys/netinet/tcp_output.c     1995/11/03 22:08:08     1.16
#--- src/sys/netinet/tcp_output.c     1995/12/05 17:46:35     1.17 RELENG_2_1_0
# (bogus example, but...)
#
	if ($difftype eq '-u') {
	    $f1 = '---';
	    $f2 = '\+\+\+';
	} else {
	    $f1 = '\*\*\*';
	    $f2 = '---';
	}
	while (<RCSDIFF>) {
	    if (m|^$f1 $cvsroot|o) {
		s|$cvsroot/||o;
		if ($sym1) {
		    chop;
		    $_ .= " " . $sym1 . "\n";
		}
	    } elsif (m|^$f2 $cvsroot|o) {
		s|$cvsroot/||o;
		if ($sym2) {
		    chop;
		    $_ .= " " . $sym2 . "\n";
		}
	    }
	    print $_;
	}
	close(RCSDIFF);
}

sub getDirLogs {
    local  ($DirName) = @_;
    my ($state);

    open(RCS, "rlog -r $DirName/*,v|")  || &fatal("500 Internal Error",
				       "Failed to spawn rlog");
    $state = 0;
    while (<RCS>) {
	if ($state==0 && /Working file: (.+)$/) {
	    $filename=$1;
	    $state=1;
	}
	if ($state==1 && /head: (.+)$/) {
	    $head=$1;
	    $state=2;
	}
	if ($state==2 && (m|^date:\s+(\d+)/(\d+)/(\d+)\s+(\d+):(\d+):(\d+);|)) {
	    $yr = $1;
	    # damn 2-digit year routines :-)
	    if ($yr > 100) {
		$yr -= 1900;
	    }
	    $date = &Time::Local::timegm($6,$5,$4,$3,$2 - 1,$yr);
	    $state=3;
	    $log='';
	    next;
	}
	if ($state==3 && /^=============/) {
	    @finfo = ($head,$date,$log);
	    $fileinfo{$filename}=[ @finfo ];
	    $state=0;
	}
	if ($state==3) {
	    $log = $log . $_;
	}
    }
}

sub dolog {
	local($fullname) = @_;
	local($curbranch,$symnames);	#...

	print("Going to rlog '$fullname'\n") if ($verbose);
	open(RCS, "rlog '$fullname'|") || &fatal("500 Internal Error",
						"Failed to spawn rlog");

	while (<RCS>) {
	    print if ($verbose);
	    if (/^branch:\s+([\d\.]+)/) {
		$curbranch = $1;
	    }
	    if ($symnames) {
		if (/^\s+([^:]+):\s+([\d\.]+)/) {
		    $symrev{$1} = $2;
		    if ($revsym{$2}) {
			$revsym{$2} .= ", ";
		    }
		    $revsym{$2} .= $1;
		} else {
		    $symnames = 0;
		}
	    } elsif (/^symbolic names/) {
		$symnames = 1;
	    } elsif (/^-----/) {
		last;
	    }
	}

	if ($onlyonbranch = $input{'only_on_branch'}) {
	    ($onlyonbranch = $symrev{$onlyonbranch}) =~ s/\.0\././;
	    ($onlybranchpoint = $onlyonbranch) =~ s/\.\d+$//;
	}

# each log entry is of the form:
# ----------------------------
# revision 3.7.1.1
# date: 1995/11/29 22:15:52;  author: fenner;  state: Exp;  lines: +5 -3
# log info
# ----------------------------
	logentry:
	while (!/^=========/) {
	    $_ = <RCS>;
	    last logentry if (!defined($_));	# EOF
	    print "R:", $_ if ($verbose);
	    if (/^revision ([\d\.]+)/) {
		$rev = $1;
	    } elsif (/^========/ || /^----------------------------$/) {
		next logentry;
	    } else {
		# The rlog output is syntactically ambiguous.  We must
		# have guessed wrong about where the end of the last log
		# message was.
		# Since this is likely to happen when people put rlog output
		# in their commit messages, don't even bother keeping
		# these lines since we don't know what revision they go with
		# any more.
		next logentry;
#		&fatal("500 Internal Error","Error parsing RCS output: $_");
	    }
	    $_ = <RCS>;
	    print "D:", $_ if ($verbose);
	    if (m|^date:\s+(\d+)/(\d+)/(\d+)\s+(\d+):(\d+):(\d+);\s+author:\s+(\S+);\s+state:\s+(\S+);\s+(lines:\s+([0-9\s+-]+))?|) {
		$yr = $1;
		# damn 2-digit year routines
		if ($yr > 100) {
		    $yr -= 1900;
		}
		$date{$rev} = &Time::Local::timegm($6,$5,$4,$3,$2 - 1,$yr);
		$author{$rev} = $7;
		$state{$rev} = $8;
		$difflines{$rev} = $10;
	    } else {
		&fatal("500 Internal Error", "Error parsing RCS output: $_");
	    }
	    line:
	    while (<RCS>) {
		print "L:", $_ if ($verbose);
		next line if (/^branches:\s/);
		last line if (/^----------------------------$/ || /^=========/);
		$log{$rev} .= $_;
	    }
	    print "E:", $_ if ($verbose);
	}
	close(RCS);
	print "Done reading RCS file\n" if ($verbose);
#
# Sort the revisions into commit-date order.
	@revorder = sort {$date{$b} <=> $date{$a}} keys %date;
	print "Done sorting revisions\n" if ($verbose);
#
# HEAD is an artificial tag which is simply the highest tag number on the main
# branch, unless there is a branch tag in the RCS file in which case it's the
# highest revision on that branch.  Find it by looking through @revorder; it
# is the first commit listed on the appropriate branch.
	$headrev = $curbranch || "1";
	revision:
	for ($i = 0; $i <= $#revorder; $i++) {
	    if ($revorder[$i] =~ /^(\S*)\.\d+$/ && $headrev eq $1) {
		if ($revsym{$revorder[$i]}) {
		    $revsym{$revorder[$i]} .= ", ";
		}
		$revsym{$revorder[$i]} .= "HEAD";
		$symrev{"HEAD"} = $revorder[$i];
		last revision;
	    }
	}
	print "Done finding HEAD\n" if ($verbose);
#
# Now that we know all of the revision numbers, we can associate
# absolute revision numbers with all of the symbolic names, and
# pass them to the form so that the same association doesn't have
# to be built then.
#
# should make this a case-insensitive sort
	foreach (sort keys %symrev) {
	    $rev = $symrev{$_};
	    if ($rev =~ /^(\d+(\.\d+)+)\.0\.(\d+)$/) {
		push(@branchnames, $_);
		#
		# A revision number of A.B.0.D really translates into
		# "the highest current revision on branch A.B.D".
		#
		# If there is no branch A.B.D, then it translates into
		# the head A.B .
		#
		$head = $1;
		$branch = $3;
		$regex = $head . "." . $branch;
		$regex =~ s/\./\./g;
		#             <
		#           \____/
		$rev = $head;

		revision:
		foreach $r (@revorder) {
		    if ($r =~ /^${regex}/) {
			$rev = $head . "." . $branch;
			last revision;
		    }
		}
		$revsym{$rev} .= ", " if ($revsym{$rev});
		$revsym{$rev} .= $_;
		if ($rev ne $head) {
		    $branchpoint{$head} .= ", " if ($branchpoint{$head});
		    $branchpoint{$head} .= $_;
		}
	    }
	    $sel .= "<OPTION VALUE=\"${rev}:${_}\">$_\n";
	}
	print "Done associating revisions with branches\n" if ($verbose);
        print &html_header("CVS log for $where");
	($upwhere = $where) =~ s|(Attic/)?[^/]+$||;
        ($filename = $where) =~ s|^.*/||;
        $backurl = $scriptname . "/" . $upwhere . $query;
	print &link($backicon, "$backurl#$filename"),
              " <b>Up to ", &clickablePath($upwhere, 1), "</b><p>\n";
	print "<A HREF=\"#diff\">Request diff between arbitrary revisions</A>\n";
	print "<HR NOSHADE>\n";
	if ($curbranch) {
	    print "Default branch is ";
	    print ($revsym{$curbranch} || $curbranch);
	} else {
	    print "No default branch";
	}
	print "<BR>\n";
# The other possible U.I. I can see is to have each revision be hot
# and have the first one you click do ?r1=foo
# and since there's no r2 it keeps going & the next one you click
# adds ?r2=foo and performs the query.
# I suppose there's no reason we can't try both and see which one
# people prefer...

        $mimetype = &getMimeTypeFromSuffix ($fullname);
        $defaultTextPlain = ($mimetype eq "text/plain");
	for ($i = 0; $i <= $#revorder; $i++) {
	    $_ = $revorder[$i];
	    ($br = $_) =~ s/\.\d+$//;
	    next if ($onlyonbranch && $br ne $onlyonbranch &&
					    $_ ne $onlybranchpoint);
	    print "<a NAME=\"rev$_\"></a>";
	    print "<HR NOSHADE>";
	    foreach $sym (split(", ", $revsym{$_})) {
		print "<a NAME=\"$sym\"></a>";
	    }
	    if ($revsym{$br} && !$nameprinted{$br}) {
		foreach $sym (split(", ", $revsym{$br})) {
		    print "<a NAME=\"$sym\"></a>";
		}
		$nameprinted{$br}++;
	    }
	    print "\n";
	    print "<A HREF=\"$scriptname/$checkoutMagic/$where?rev=$_" . 
		$barequery . "\"><b>$_</b></A>";
	    print " / <A HREF=\"$scriptname/$checkoutMagic/$where?rev=$_&content-type=text/plain" . 
		$barequery . "\">(text)</A>" if (not $defaultTextPlain);
	    if (/^1\.1\.1\.\d+$/) {
		print " <i>(vendor branch)</i>";
	    }
	    print " <i>" . scalar gmtime($date{$_}) . " UTC</i>; ";
	    print readableTime(timegm(localtime(time())) - $date{$_},1) . " ago";
	    print " by ";
	    print "<i>" . $author{$_} . "</i>\n";
	    if ($revsym{$_}) {
		print "<BR>CVS Tags: <b>$revsym{$_}</b>";
	    }
	    if ($revsym{$br})  {
		if ($revsym{$_}) {
		    print "; ";
		} else {
		    print "<BR>";
		}
		print "Branch: <b>$revsym{$br}</b>\n";
	    }
	    if ($branchpoint{$_}) {
		if ($revsym{$br} || $revsym{$_}) {
		    print "; ";
		} else {
		    print "<BR>";
		}
		print "Branch point for: <b>$branchpoint{$_}</b>\n";
	    }
	    # Find the previous revision on this branch.
	    @prevrev = split(/\./, $_);
	    if (--$prevrev[$#prevrev] == 0) {
		# If it was X.Y.Z.1, just make it X.Y
		if ($#prevrev > 1) {
		    pop(@prevrev);
		    pop(@prevrev);
		} else {
		    # It was rev 1.1 (XXX does CVS use revisions
		    # greater than 1.x?)
		    if ($prevrev[0] != 1) {
			print "<i>* I can't figure out the previous revision! *</i>\n";
		    }
		}
	    }
	    if ($prevrev[$#prevrev] != 0) {
		$prev = join(".", @prevrev);
		if ($difflines{$_}) {
		    print "<BR>Changed since <b>$prev</b>: $difflines{$_} lines";
		}
		print "<BR><A HREF=\"${scriptwhere}.diff?r1=$prev";
		print "&r2=$_" . $barequery . "\">Diffs to $prev</A>\n";
		if (!$hr_default) { # offer a human readable version if not default
		    print "<A HREF=\"${scriptwhere}.diff?r1=$prev";
		    print "&r2=$_" . $barequery . "&f=h\">(nice version)</A>\n";
		}
		#
		# Plus, if it's on a branch, and it's not a vendor branch,
		# offer to diff with the immediately-preceding commit if it
		# is not the previous revision as calculated above
		# and if it is on the HEAD (or at least on a higher branch)
		# (e.g. change gets committed and then brought
		# over to -stable)
		if (!/^1\.1\.1\.\d+$/ && ($i != $#revorder) &&
					($prev ne $revorder[$i+1])) {
		    @tmp1 = split(/\./, $revorder[$i+1]);
		    @tmp2 = split(/\./, $_);
		    if ($#tmp1 < $#tmp2) {
			print "; <A HREF=\"${scriptwhere}.diff?r1=$revorder[$i+1]";
			print "&r2=$_" . $barequery .
                            "\">Diffs to $revorder[$i+1]</A>\n";
			if (!$hr_default) { # offer a human readable version if not default
			    print "<A HREF=\"${scriptwhere}.diff?r1=$revorder[$i+1]";
			    print "&r2=$_" . $barequery .
				"&f=h\">(nice version)</A>\n";

			}

		    }
		}
	    }
	    if ($state{$_} eq "dead") {
		print "<BR><B><I>FILE REMOVED</I></B>\n";
	    }
	    print "<PRE>\n";
	    print &htmlify($log{$_}, 1);
	    print "</PRE>\n";
	}
	print "<A NAME=diff>\n";
        print "<HR NOSHADE>";
	print "This form allows you to request diff's between any two\n";
	print "revisions of a file.  You may select a symbolic revision\n";
	print "name using the selection box or you may type in a numeric\n";
	print "name using the type-in text box.\n";
	print "</A><P>\n";
	print "<FORM METHOD=\"GET\" ACTION=\"${scriptwhere}.diff\">\n";
        foreach (@usedvars) {
	    if ($input{$_}) {
		print "<INPUT TYPE=HIDDEN NAME=\"$_\" VALUE=\"$input{$_}\">\n";
	    }
	}
	print "Diffs between \n";
	print "<SELECT NAME=\"r1\">\n";
	print "<OPTION VALUE=\"text\" SELECTED>Use Text Field\n";
	print $sel;
	print "</SELECT>\n";
	print "<INPUT TYPE=\"TEXT\" SIZE=\"$inputTextSize\" NAME=\"tr1\" VALUE=\"$revorder[$#revorder]\">\n";
	print " and \n";
	print "<SELECT NAME=\"r2\">\n";
	print "<OPTION VALUE=\"text\" SELECTED>Use Text Field\n";
	print $sel;
	print "</SELECT>\n";
	print "<INPUT TYPE=\"TEXT\" SIZE=\"$inputTextSize\" NAME=\"tr2\" VALUE=\"$revorder[0]\">\n";
        print "<BR><TABLE>";
        print "<tr><td><INPUT TYPE=RADIO NAME=\"f\" VALUE=h CHECKED> Human readable</td>\n";
	print "<td><INPUT TYPE=RADIO NAME=\"f\" VALUE=u> Unidiff</td></tr>\n";
	print "<tr><td><INPUT TYPE=RADIO NAME=\"f\" VALUE=c> Context diff</td>\n";
	print "<td><INPUT TYPE=RADIO NAME=\"f\" VALUE=s> Side-by-Side</td></tr>\n";
        print "</TABLE>";
	print "<INPUT TYPE=SUBMIT VALUE=\"Get Diffs\">\n";
	print "</FORM>\n";
	print "<HR noshade>\n";
	print "<A name=branch>\n";
	print "You may select to see revision information from only\n";
	print "a single branch.\n";
	print "</A><P>\n";
	print "<FORM METHOD=\"GET\" ACTION=\"$scriptwhere\">\n";
        foreach (@usedvars) {
	    if ($input{$_}) {
		print "<INPUT TYPE=HIDDEN NAME=\"$_\" VALUE=\"$input{$_}\">\n";
	    }
	}
	print "Branch: \n";
	print "<SELECT NAME=\"only_on_branch\">\n";
	print "<OPTION VALUE=\"\"";
	print " SELECTED" if ($input{"only_on_branch"} eq "");
	print ">Show all branches\n";
	foreach (sort @branchnames) {
		print "<OPTION";
		print " SELECTED" if ($input{"only_on_branch"} eq $_);
		print ">${_}\n";
	}
	print "</SELECT>\n";
	print "<INPUT TYPE=SUBMIT VALUE=\"View Branch\">\n";
	print "</FORM>\n";
        print &html_footer;
	print "</BODY></HTML>\n";
}

sub flush_diff_rows ($$$$)
{
    local $j;
    my ($leftColRef,$rightColRef,$leftRow,$rightRow) = @_;
    if ($state eq "PreChangeRemove") {          # we just got remove-lines before
      for ($j = 0 ; $j < $leftRow; $j++) {
          print  "<tr><td bgcolor=\"$diffcolorRemove\">@$leftColRef[$j]</td>";
          print  "<td bgcolor=\"$diffcolorEmpty\">&nbsp;</td></tr>\n";
      }
    }
    elsif ($state eq "PreChange") {             # state eq "PreChange"
      # we got removes with subsequent adds
      for ($j = 0; $j < $leftRow || $j < $rightRow ; $j++) {  # dump out both cols
          print  "<tr>";
          if ($j < $leftRow) { print  "<td bgcolor=\"$diffcolorChange\">@$leftColRef[$j]</td>"; }
          else { print  "<td bgcolor=\"$diffcolorDarkChange\">&nbsp;</td>"; }
          if ($j < $rightRow) { print  "<td bgcolor=\"$diffcolorChange\">@$rightColRef[$j]</td>"; }
          else { print  "<td bgcolor=\"$diffcolorDarkChange\">&nbsp;</td>"; }
          print  "</tr>\n";
      }
    }
}

##
# Function to generate Human readable diff-files
# human_readable_diff(String revision_to_return_to);
##
sub human_readable_diff($)
{
  local $ii,$difftxt, $where_nd, $filename, $pathname;
  my ($rev) = @_;

  ($where_nd = $where) =~ s/.diff$//;
  ($filename = $where_nd) =~ s/^.*\///;
  ($pathname = $where_nd) =~ s/(Attic\/)?[^\/]*$//;

  print  "<html>\n<head>\n<title>CVS diff for $where_nd</title>\n</head>\n";
  print  "<BODY BGCOLOR=\"$backcolor\">\n";

  print "<table width=\"100%\" border=0 cellspacing=0 cellpadding=1 bgcolor=\"$diffcolorHeading\">";
  print "<tr valign=bottom><td>";
  ($scriptwhere_nd = $scriptwhere) =~ s/.diff$//;
  print  "<a href=\"$scriptwhere_nd$query#rev$rev\">$backicon";
  print "</a> <b>Return to ", &link("$filename","$scriptwhere_nd$query#rev$rev")," CVS log";
  print "</b> $fileicon</td>";
  
  print "<td align=right>$diricon <b>Up to ", &clickablePath($pathname, 1), "</b></td>";
  print "</tr></table>";

  print  "<h3 align=center>Diff for /$where_nd between version $rev1 and $rev2</h2>\n";

  print  "<table border=0 cellspacing=0 cellpadding=0 width=100%>\n";
  print  "<tr bgcolor=#ffffff><th width=\"50%\">version $rev1</th><th witdh=\"50%\">version $rev2</th></tr>";

  $fs="<font face=\"$difffontface\" size=\"$difffontsize\">";
  $fe="</font>";

  $leftRow = 0;
  $rightRow = 0;
  
  while (<RCSDIFF>) {
      next unless $. > 7;

      $difftxt = $_;
      
      if ($difftxt =~ /^@@/) {
	  ($oldline,$newline,$funname) = $difftxt =~ /@@ \-([0-9]+).*\+([0-9]+).*@@(.*)/;
          print  "<tr bgcolor=\"$diffcolorHeading\"><td width=\"50%\">";
	  print  "<table width=100% border=1 cellpadding=5><tr><td><b>Line $oldline</b>";
	  print  "&nbsp;<font size=-1>$funname</font></td></tr></table>";
          print  "</td><td width=\"50%\">";
	  print  "<table width=100% border=1 cellpadding=5><tr><td><b>Line $newline</b>";
	  print  "&nbsp;<font size=-1>$funname</font></td></tr></table>";
	  print  "</td><tr>\n";
	  $state = "dump";
	  $leftRow = 0;
	  $rightRow = 0;
      }
      else {
	  ($diffcode,$rest) = $difftxt =~ /^([-+ ])(.*)/;
	  $_= $rest;
########
# quote special characters
# according to RFC 1866,Hypertext Markup Language 2.0,
# 9.7.1. Numeric and Special Graphic Entity Set
# (Hen)
#######
	  s/&/&amp;/g;
	  s/\"/&quot;/g; 
	  s/</&lt;/g; 
	  s/>/&gt;/g; 

	  # replace <tab> and <space>
	  if ($hr_breakable) {
	      # make every other space 'breakable'
	      s/	/&nbsp; &nbsp; &nbsp; &nbsp; /g;    # <tab>
	      s/   /&nbsp; &nbsp;/g;                        # 3 * <space>
	      s/  /&nbsp; /g;                               # 2 * <space>
	      # leave single space as it is
	  }
	  else {
	      s/	/&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;/g; 
	      s/ /&nbsp;/g;
	  }
	  
	  # Add fontface, size
	  $_ = "$fs&nbsp;$_$fe";
	  
	  #########
	  # little state machine to parse unified-diff output (Hen, zeller@think.de)
	  # in order to get some nice 'ediff'-mode output
	  # states:
	  #  "dump"             - just dump the value
	  #  "PreChangeRemove"  - we began with '-' .. so this could be the start of a 'change' area or just remove
	  #  "PreChange"        - okey, we got several '-' lines and moved to '+' lines -> this is a change block
	  ##########

	  if ($diffcode eq '+') {
	      if ($state eq "dump") {  # 'change' never begins with '+': just dump out value
		  print  "<tr><td bgcolor=\"$diffcolorEmpty\">&nbsp;</td><td bgcolor=\"$diffcolorAdd\">$_</td></tr>\n";
	      }
	      else {                   # we got minus before
		  $state = "PreChange";
		  @rightCol[$rightRow++] = $_;
	      }
	  } 
	  elsif ($diffcode eq '-') {
	      $state = "PreChangeRemove";
	      @leftCol[$leftRow++] = $_;
        }
        else {  # empty diffcode
            flush_diff_rows \@leftCol, \@rightCol, $leftRow, $rightRow;
	      print  "<tr><td>$_</td><td>$_</td></tr>\n";
	      $state = "dump";
	      $leftRow = 0;
	      $rightRow = 0;
	  }
      }
  }
  flush_diff_rows \@leftCol, \@rightCol, $leftRow, $rightRow;

  # state is empty if we didn't have any change
  if (!$state) {
      print "<tr><td colspan=2>&nbsp;</td></tr>";
      print "<tr bgcolor=\"$diffcolorEmpty\" >";
      print "<td colspan=2 align=center><b>- No viewable Change -</b></td></tr>";
  }
  print  "</table>";
  close(<RCSDIFF>);

  # print legend
  print  "<br><hr noshade width=100%><table border=1><tr><td>";
  print  "Legend:<br><table border=0 cellspacing=0 cellpadding=1>\n";
  print  "<tr><td align=center bgcolor=\"$diffcolorRemove\">Removed in v.$rev1</td><td bgcolor=\"$diffcolorEmpty\">&nbsp;</td></tr>";
  print  "<tr bgcolor=\"$diffcolorChange\"><td align=center colspan=2>changed lines</td></tr>";
  print  "<tr><td bgcolor=\"$diffcolorEmpty\">&nbsp;</td><td align=center bgcolor=\"$diffcolorAdd\">Added in v.$rev2</td></tr>";
  print  "</table></td></tr></table>\n";
  print  "</body>\n</html>\n";
}

sub plural_write ($$)
{
    my ($num,$text) = @_;
    if ($num != 1) {
	$text = $text . "s";
    }
    if ($num > 0) {
	return $num . " " . $text;
    } else {
	return "";
    }
}

##
# print readable timestamp in terms of
# '..time ago'
# H. Zeller <zeller@think.de>
##
sub readableTime ($$)
{
    local $i, $break, $retval;
    my ($secs,$long) = @_;

    # this function works correct for time >= 2 seconds
    if ($secs < 2) {
	return "very little time";
    }

    local %desc = (1 , 'second',
		   60, 'minute',
		   3600, 'hour',
		   86400, 'day',
		   604800, 'week',
		   2628000, 'month',
		   31536000, 'year');
    local @breaks = sort {$a <=> $b} keys %desc;
    $i = 0;
    while ($i <= $#breaks && $secs >= 2 * $breaks[$i]) { 
	$i++;
    }
    $i--;
    $break = $breaks[$i];
    $retval = plural_write(int ($secs / $break), $desc{"$break"});

    if ($long==1 && $i > 0) {
	local $rest = $secs % $break;
	$i--;
	$break = $breaks[$i];
	$resttime = plural_write(int ($rest / $break), 
				$desc{"$break"});
	if ($resttime) {
	    $retval = $retval . ", " . $resttime;
	}
    }

    return $retval;
}

##
# clickablePath(String pathname, boolean last_item_clickable)
#
# returns a html-ified path whereas each directory is a link for
# faster navigation. last_item_clickable controls whether the
# basename (last directory/file) is a link as well
##
sub clickablePath($$) {
    my ($pathname,$clickLast) = @_;    
    local $retval = '';
    
    if ($pathname eq '') {
	# mmh, a selection box would be fine here ..
	$retval = $retval . " [$cvstree]";
    } else {
	$retval = $retval . " <a href=\"${scriptname}${query}\">[$cvstree]</a>";
	$wherepath = '';
	foreach (split(/\//, $pathname)) {
	    $retval = $retval . " / ";
	    $wherepath = $wherepath . '/' . $_;
	    if ($clickLast || $wherepath ne "/$pathname") {
		$retval = $retval . "<a href=\"${scriptname}${wherepath}${query}\">$_</a>";
	    } else { # do not make a link to the current dir
		$retval = $retval .  $_;
	    }
	}
    }
    return $retval;
}

sub fileSortCmp {
    my ($comp)=0;
    my ($c,$d,$af,$bf);

    if ($bydate==1) {
	($af=$a) =~ s/,v$//;
	($bf=$b) =~ s/,v$//;
	my ($head1,$date1,$log1)=@{$fileinfo{$af}};
	my ($head2,$date2,$log2)=@{$fileinfo{$bf}};
	if ($date1  && $date2) {
	    $comp = ($date2 <=> $date1);
	}
    }
    if ($comp == 0) {
	$ad=((-d "$fullname/$a")?"D":"F");
	$bd=((-d "$fullname/$b")?"D":"F");
	($c=$a)=~s|.*/||;
	($d=$b)=~s|.*/||;
	$comp = ("$ad$c" cmp "$bd$d");
    }
    return $comp;
}

sub cvsroot {
    return '' if $cvstree eq $cvstreedefault;
    return "&cvsroot=" . $cvstree;
}
