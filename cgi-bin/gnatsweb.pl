#!/usr/bin/perl -w
#
# Gnatsweb - web front-end to gnats
#
# Copyright 1998-1999 - Matt Gerassimoff
# and Ken Cox <kenstir@senteinc.com>
#
# $Id: gnatsweb.pl,v 1.1 1999/08/04 02:40:22 jsm Exp $
#

#-----------------------------------------------------------------------------
# Site-specific customization -
#
#     User serviceable parts - variables and subroutines.
#
#     We suggest you don't edit these variables here, but instead put
#     them in a file called 'gnatsweb-site.pl' in the same directory.
#     That way, when a new version of gnatsweb is released, you won't
#     need to edit them again.
#
#     For an example of what you can do with the site_callback
#     subroutine, see gnatsweb-site-sente.pl.
#

# Info about your gnats host.
$site_gnats_host = 'localhost';
$site_gnats_port = 1529;

# Set to true if you compiled gnats with GNATS_RELEASE_BASED defined.
$site_release_based = 0;

# Name you want in the page banner.
$site_banner_text = 'gnatsweb';

# Program to send email notifications.
if (-x '/usr/sbin/sendmail')
{
  $site_mailer = '/usr/sbin/sendmail -oi -t';
}
elsif (-x '/usr/lib/sendmail')
{
  $site_mailer = '/usr/lib/sendmail -oi -t';
}
else
{
  die("Can't locate 'sendmail'; must set \$site_mailer in gnats-site.pl");
}

# site_callback -
#
#     If defined, this subroutine gets called at various times.  The
#     reason it is being called is indicated by the $reason argument.
#     It can return undef, in which case gnatsweb does its default
#     thing.  Or, it can return a piece of HTML to implement
#     site-specific behavior or appearance.
#
#     Sorry, the reasons are not documented.  Either put a call to
#     'warn' into your gnats-site.pl file, or search this file for 'cb('.
#
# arguments:
#     $reason - reason for the call.  Each reason is unique.
#     @args   - additional parameters may be provided in @args.
#
# returns:
#     undef     - take no special action
#     string    - string is used by gnatsweb according to $reason
#
# example:
#     See gnatsweb-site-sente.pl for an extended example.
#
#     sub site_callback {
#         my($reason, @args) = @_;
#         if ($reason eq 'sendpr_description') {
#             return 'default description text used in sendpr form';
#         }
#         undef;
#     }
#

# end customization
#-----------------------------------------------------------------------------

use CGI 2.50 qw/:standard :netscape/;
use CGI::Carp qw/fatalsToBrowser/;
use Socket;
use IO::Handle;

# get RCS tag as just a number
$VERSION = '2.4';
( $REVISION = '$Revision: 1.1 $ ' ) =~ s/.Revision: (.*) ../$1/;

# width of text fields
$textwidth = 60;

# where to get help -- a web site with translated info documentation
$gnats_info_top = "http://www.hyperreal.org/info/gnuinfo/index";

# bits in %fieldnames has (set=yes not-set=no)
$MULTILINE    = 1;   # whether field is multi line
$SENDEXCLUDE  = 2;   # whether the send command should exclude the field
$REASONCHANGE = 4;   # whether change to a field requires reason
$ENUM         = 8;   # whether field should be displayed as enumerated
$EDITEXCLUDE  = 16;  # if set, don't display on edit page
$AUDITINCLUDE = 32;  # if set, save changes in Audit-Trail

$REPLY_CONT = 1;
$REPLY_END = 2;

$CODE_GREETING = 200;
$CODE_OK = 210;
$CODE_PR_READY = 220;
$CODE_CLOSING = 205;
$CODE_INFORMATION = 230;
$CODE_HELLO = 250;

$CODE_INVALID_PR = 410;
$CODE_INVALID_CATEGORY = 420;
$CODE_UNREADABLE_PR = 430;
$CODE_NO_PRS = 440;
$CODE_NO_KERBEROS = 450;
$CODE_INVALID_SUBMITTER = 460;
$CODE_INVALID_STATE = 461;
$CODE_INVALID_RESPONSIBLE = 465;
$CODE_INVALID_DATE = 468;
$CODE_FILE_ERROR = 480;
$CODE_LOCKED_PR = 490;
$CODE_GNATS_LOCKED = 491;
$CODE_PR_NOT_LOCKED = 495;

$CODE_ERROR = 500;
$CODE_NO_ACCESS = 520;

$| = 1; # flush output after each print

sub gerror
{
  my($text) = @_;
  my $prog = $0;
  $prog =~ s@.*/@@;
  #print "<pre>$prog: $text\n</pre>\n";
  print "<h2>Error: $text\n</h2>\n";
}

# Close the client socket and exit.  The exit can be suppressed by:
#     local($suppress_client_exit) = 1;
sub client_exit
{
  close(SOCK);
  exit() unless defined($suppress_client_exit);
}

sub server_reply
{
  my($state, $text, $type);
  $_ = <SOCK>;
  if(/(\d+)([- ]?)(.*$)/)
  {
    $state = $1;
    $text = $3;
    if($2 eq '-')
    {
      $type = $REPLY_CONT;
    }
    else
    {
      if($2 ne ' ')
      {
        gerror("bad type of reply from server");
      }
      $type = $REPLY_END;
    }
    return ($state, $text, $type);
  }
  return (undef, undef, undef);
}

sub read_server
{
  my(@text);

  while(<SOCK>)
  {
    if(/^\.\r/)
    {
      return @text;
    }
    $_ =~ s/[\r\n]//g;
    # Lines which begin with a '.' are escaped by gnatsd with another '.'
    $_ =~ s/^\.\././;
    push(@text, $_);
  }
}

sub get_reply
{
  my($state, $text, $type) = server_reply();
  my(@rettext) = ($text);
  if($state == $CODE_GREETING)
  {
    while($type == $REPLY_CONT)
    {
      ($state, $text, $type) = server_reply();
      if(!defined($state))
      {
        gerror("null reply from the server");
      }
      push(@rettext, $text);
    }
  }
  elsif($state == $CODE_OK || $state == $CODE_HELLO)
  {
    # nothing
  }
  elsif($state == $CODE_CLOSING)
  {
    # nothing
  }
  elsif($state == $CODE_PR_READY)
  {
    @rettext = read_server();
  }
  elsif($state == $CODE_INFORMATION)
  {
    ($state, $text, $type) = server_reply();
    while($type == $REPLY_CONT)
    {
      push(@rettext, $text);
      ($state, $text, $type) = server_reply();
    }
  }
  elsif($state == $CODE_INVALID_PR)
  {
    $text =~ / (.*)/;
    gerror("couldn't find $1");
    client_exit();
  }
  elsif($state == $CODE_INVALID_CATEGORY)
  {
    $text =~ / (.*)/;
    gerror($1);
    client_exit();
  }
  elsif($state == $CODE_INVALID_SUBMITTER)
  {
    $text =~ / (.*)/;
    gerror($1);
    client_exit();
  }
  elsif($state == $CODE_INVALID_STATE)
  {
    $text =~ / (.*)/;
    gerror("no such state $1");
    client_exit();
  }
  elsif($state == $CODE_INVALID_RESPONSIBLE)
  {
    $text =~ / (.*)/;
    gerror($1);
    client_exit();
  }
  elsif($state == $CODE_INVALID_DATE)
  {
    $text =~ / (.*)/;
    gerror($1);
    client_exit();
  }
  elsif($state == $CODE_UNREADABLE_PR)
  {
    $text =~ / (.*)/;
    gerror("couldn't read $1");
    client_exit();
  }
  elsif($state == $CODE_PR_NOT_LOCKED)
  {
    gerror("PR is not locked");
    client_exit();
  }
  elsif($state == $CODE_LOCKED_PR ||
        $state == $CODE_FILE_ERROR ||
	$state == $CODE_ERROR)
  {
    $text =~ s/\r//g;
    gerror($text);
    client_exit();
    @rettext = (); # may get here if exit suppressed
  }
  elsif($state == $CODE_GNATS_LOCKED)
  {
    gerror("lock file exists");
    client_exit();
  }
  elsif($state == $CODE_NO_PRS)
  {
    gerror("no PRs matched");
    client_exit();
  }
  elsif($state == $CODE_NO_KERBEROS)
  {
    gerror("no Kerberos support, authentication failed");
    client_exit();
  }
  elsif($state == $CODE_NO_ACCESS)
  {
    gerror("access denied");
    client_exit();
    @rettext = (); # may get here if exit suppressed
  }
  else
  {
    gerror("cannot understand $state '$text'");
  }
  return @rettext;
}

sub client_init
{
  my($iaddr, $paddr, $proto, $line, $length);

  $iaddr = inet_aton($site_gnats_host);
  $paddr = sockaddr_in($site_gnats_port, $iaddr);

  $proto = getprotobyname('tcp');
  if(!socket(SOCK, PF_INET, SOCK_STREAM, $proto))
  {
    gerror("socket: $!");
    exit();
  }
  if(!connect(SOCK, $paddr))
  {
    gerror("connect: $!");
    exit();
  }
  SOCK->autoflush(1);
  return get_reply();
}

# to debug:
#     local($client_cmd_debug) = 1;
#     client_cmd(...);
sub client_cmd
{
  my($cmd) = @_;
  print SOCK "$cmd\n";
  print "<tt>client_cmd: $cmd</tt><br>\n" if defined($client_cmd_debug);
  return get_reply();
}

sub sendpr
{
  my $page = 'Create PR';
  page_start_html($page);
  page_heading($page, 'Create Problem Report', 1);

  # remove "all" from arrays
  shift(@category);
  shift(@severity);
  shift(@priority);
  shift(@class);
  shift(@confidential);
  shift(@responsible);
  shift(@state);
  shift(@submitter_id);

  print $q->start_form(),
	"<table>";
  print "<tr><td><b>Reporter's email:</b><td>",
        $q->textfield(-name=>'email',
                      -default=>$email,
                      -size=>$textwidth),
	"<tr><td><b>Send a CC of this report only to:</b><td>",
	$q->textfield(-name=>'cc',
	              -default=>$cc,
		      -size=>$textwidth),
	"<tr><td><b>Others to notify<br>of updates:</b><td>",
	$q->textfield(-name=>'X-GNATS-Notify',
		      -size=>$textwidth),
        # a blank row, to separate header info from PR info
        "<tr><td>&nbsp;<td>&nbsp;\n";

  foreach (@fieldnames)
  {
    next if ($fieldnames{$_} & $SENDEXCLUDE);
    my $lc_fieldname = field2param($_);

    # Get default value from site_callback if provided, otherwise take
    # our defaults.
    my $default;
    $default = 'serious'                  if /Severity/;
    $default = 'medium'                   if /Priority/;
    $default = $submitter_id || 'unknown' if /Submitter-Id/;
    $default = $originator                if /Originator/;
    $default = cb("sendpr_$lc_fieldname") || $default;

    if ($fieldnames{$_} & $ENUM)
    {
      print "<tr><td><b>$_:</b><td>",
            $q->popup_menu(-name=>$_,
                           -values=>\@$lc_fieldname,
                           -default=>$default);
    }
    elsif ($fieldnames{$_} & $MULTILINE)
    {
      my $rows = 4;
      $rows = 8 if /Description/;
      $rows = 2 if /Environment/;
      print "<tr><td valign=top><b>$_:</b><td>",
            $q->textarea(-name=>$_,
                         -cols=>$textwidth,
                         -rows=>$rows,
                         -default=>$default);
    }
    else
    {
      print "<tr><td><b>$_:</b><td>",
            $q->textfield(-name=>$_,
                          -size=>$textwidth,
                          -default=>$default);
    }
    print "\n";
  }
  print "</table>",
	$q->submit('cmd', 'submit'),
	" or ",
	$q->reset(-name=>'reset'),
	$q->end_form();

  page_footer($page);
  page_end_html($page);
}

# validate_email_field -
#     Used by validate_new_pr to check email address fields in a new PR.
sub validate_email_field
{
  my($fieldname, $fieldval, $required) = @_;

  my $blank = ($fieldval =~ /^\s*$/);
  if ($required && $blank)
  {
    return "$fieldname is blank";
  }
  # From rkimball@vgi.com, allows @ only if it's followed by what looks
  # more or less like a domain name.
  my $email_addr = '[^@]+(@\S+\.\S+)?';
  if (!$blank && $fieldval !~ /^\s*($email_addr\s*)+$/)
  {
    return "'$fieldval' doesn't look like a valid email address (xxx\@xxx.xxx)";
  }
  return '';
}

# validate_new_pr -
#     Make sure fields have reasonable values before submitting a new PR.
sub validate_new_pr
{
  my(%fields) = @_;
  my(@errors) = ();
  my $err;

  # validate email fields
  $err = validate_email_field('E-mail Address', $fields{'email'}, 'required');
  push(@errors, $err) if $err;
  $err = validate_email_field('CC', $fields{'cc'});
  push(@errors, $err) if $err;
  $err = validate_email_field('X-GNATS-Notify', $fields{'X-GNATS-Notify'});
  push(@errors, $err) if $err;

  # validate some other fields
  push(@errors, "Synopsis is blank")
        if($fields{'Synopsis'} =~ /^\s*$/);
  push(@errors, "Release is blank")
        if($fields{'Release'} =~ /^\s*$/);
  push(@errors, "Submitter-Id is 'unknown'")
        if($fields{'Submitter-Id'} eq 'unknown');

  @errors;
}

sub submitnewpr
{
  my $page = 'Create PR Results';
  page_start_html($page);

  my $debug = 0;
  my(@values, $key);
  my(%fields);

  foreach $key ($q->param)
  {
    my $val = $q->param($key);
    if($fieldnames{$key} && ($fieldnames{$key} & $MULTILINE))
    {
      $val = fix_multiline_val($val);
    }
    $fields{$key} = $val;
  }

  # Make sure the pr is valid.
  my(@errors) = validate_new_pr(%fields);
  if (@errors)
  {
    page_heading($page, 'Error');
    print "<h3>Your problem report has not been sent.</h3>\n",
          "Fix the following problems, then submit the problem report again:",
          $q->ul($q->li(\@errors));
    return;
  }

  # Supply a default value for Originator
  $fields{'Originator'} = $fields{'Originator'} || $fields{'email'};

  # Compose the message
  my $text = unparsepr('send', %fields);
  $text = <<EOT . $text;
To: $config{'GNATS_ADDR'}
CC: $fields{'cc'}
Subject: $fields{'Synopsis'}
From: $fields{'email'}
Reply-To: $fields{'email'}
X-Send-Pr-Version: gnatsweb-$VERSION ($REVISION)
X-GNATS-Notify: $fields{'X-GNATS-Notify'}

EOT

  # Allow debugging
  if($debug)
  {
    print "<h3>debugging -- PR NOT SENT</h3>",
          $q->pre($q->escapeHTML($text));
    page_end_html($page);
    return;
  }

  # Send the message
  if(!open(MAIL, "|$site_mailer"))
  {
    page_heading($page, 'Error');
    print "<h3>Error invoking $site_mailer</h3>";
    return;
  }
  print MAIL $text;
  if(!close(MAIL))
  {
    page_heading($page, 'Error');
    print "<h3>Bad pipe to $site_mailer</h3>";
    exit;
  }

  # Give feedback for success
  page_heading($page, 'Problem Report Sent');
  print "Thank you for your report.  It will take a short while for
your report to be processed.  When it is, you will receive
an automated message about it, containing the Problem Report
number, and the developer who has been assigned to
investigate the problem.";

  page_footer($page);
  page_end_html($page);
}

sub view
{
  my($viewaudit, $tmp) = @_;

  my $page = 'View PR';
  page_start_html($page);

  # $pr must be 'local' to be available to site callback
  local($pr) = $q->param('pr');
  if(!$pr)
  {
    page_heading($page, 'Error');
    print "<h3>You must specify a problem report number</h3>";
    return;
  }
  page_heading($page, "View Problem Report: $pr", 1);

  # %fields must be 'local' to be available to site callback
  local(%fields) = readpr($pr);

  print $q->start_form(),
	$q->hidden('pr', $pr);

  # print 'edit' and 'view audit-trail' buttons as appropriate
  print $q->submit('cmd', 'edit')             if (can_edit());
  print " or "                                if (can_edit() && !$viewaudit);
  print $q->submit('cmd', 'view audit-trail') if (!$viewaudit);

  # print a convenient 'mailto' link
  my $mailto  = $q->escape(scalar(interested_parties($pr, %fields)));
  my $subject = $q->escape("Re: $fields{'Category'}/$pr");
  my $body    = $q->escape(get_viewpr_url($pr));
  print " or ",
        "<a href=\"mailto:$mailto?Subject=$subject&Body=$body\">",
        "send email to interested parties</a>";

  print $q->hr(),
        "<table>";
  print "<tr><td><b>Reporter's email:</b><td>",
        $q->tt($fields{'Reply-To'}),
	"<tr><td><b>Others to notify<br>of updates:</b><td>",
	$q->tt($fields{'X-GNATS-Notify'}),
        # a blank row, to separate header info from PR info
        "<tr><td>&nbsp;<td>&nbsp;\n";

  foreach (@fieldnames)
  {
    next if $_ eq 'Audit-Trail';
    my $val = $q->escapeHTML($fields{$_});
    my $valign = '';
    if ($fieldnames{$_} & $MULTILINE)
    {
      $valign = 'valign=top';
      $val =~ s/$/<br>/gm;
      $val =~ s/<br>$//; # previous substitution added one too many <br>'s
    }
    print "<tr><td nowrap $valign><b>$_:</b><td>",
          $q->tt($val), "\n";
  }
  print "</table>",
        $q->hr();

  # print 'edit' and 'view audit-trail' buttons as appropriate
  print $q->submit('cmd', 'edit')             if (can_edit());
  print " or "                                if (can_edit() && !$viewaudit);
  print $q->submit('cmd', 'view audit-trail') if (!$viewaudit);

  # print a convenient 'mailto' link
  print " or ",
        "<a href=\"mailto:$mailto?Subject=$subject\">",
        "send email to interested parties</a>";

  print $q->end_form();

  # Footer comes before the audit-trail.
  page_footer($page);

  if($viewaudit)
  {
    print "<h3>Audit Trail:</h3>\n",
          $q->pre($q->escapeHTML($fields{'Audit-Trail'}));
  }

  page_end_html($page);
}

sub edit
{
  my $page = 'Edit PR';
  page_start_html($page);

  #my $debug = 0;

  my($pr) = $q->param('pr');
  if(!$pr)
  {
    page_heading($page, 'Error');
    print "<h3>You must specify a problem report number</h3>";
    return;
  }
  page_heading($page, "Edit Problem Report: $pr", 1);

  my(%fields) = readpr($pr);

  # Trim Responsible for compatibility.
  $fields{'Responsible'} = trim_responsible($fields{'Responsible'});

  # remove "all" from arrays
  shift(@category);
  shift(@severity);
  shift(@priority);
  shift(@class);
  shift(@confidential);
  shift(@responsible);
  shift(@state);
  shift(@submitter_id);

  print $q->start_form(),
        $q->submit('cmd', 'submit edit'),
        " or ",
        $q->reset(-name=>'reset'),
	$q->hidden(-name=>'Editor', -value=>$user, -override=>1),
	$q->hidden(-name=>'Last-Modified',
		   -value=>$fields{'Last-Modified'},
		   -override=>1),
	$q->hidden(-name=>'pr', -value=>$pr, -override=>1),
        "<hr>\n";

  print "<table>";
  print "<tr><td><b>Reporter's email:</b><td>",
        $q->textfield(-name=>'Reply-To',
                      -default=>$fields{'Reply-To'},
                      -size=>$textwidth),
	"<tr><td><b>Others to notify<br>of updates:</b><td>",
	$q->textfield(-name=>'X-GNATS-Notify',
                      -default=>$fields{'X-GNATS-Notify'},
		      -size=>$textwidth),
        # a blank row, to separate header info from PR info
        "<tr><td>&nbsp;<td>&nbsp;\n";

  foreach (@fieldnames)
  {
    next if ($fieldnames{$_} && $fieldnames{$_} & $EDITEXCLUDE);
    my $lc_fieldname = field2param($_);

    if ($fieldnames{$_} && $fieldnames{$_} & $ENUM)
    {
      print "<tr><td><b>$_:</b><td>",
            $q->popup_menu(-name=>$_,
                           -values=>\@$lc_fieldname,
                           -default=>$fields{$_});
    }
    elsif ($fieldnames{$_} && $fieldnames{$_} & $MULTILINE)
    {
      my $rows = 4;
      $rows = 8 if /Description/;
      $rows = 2 if /Environment/;
      print "<tr><td valign=top><b>$_:</b><td>",
            $q->textarea(-name=>$_,
                         -cols=>$textwidth,
                         -rows=>$rows,
                         -default=>$fields{$_});
    }
    else
    {
      print "<tr><td><b>$_:</b><td>",
            $q->textfield(-name=>$_,
                          -size=>$textwidth,
                          -default=>$fields{$_});
    }
    if ($fieldnames{$_} && $fieldnames{$_} & $REASONCHANGE)
    {
      print "<tr><td valign=top><b>Reason Changed:</b><td>",
            $q->textarea(-name=>"$_-Why",
			 -default=>'',
			 -override=>1,
			 -cols=>$textwidth,
			 -rows=>2);
    }
    print "\n";
  }
  print	"</table>",
	$q->submit('cmd', 'submit edit'),
	" or ",
	$q->reset(-name=>'reset'),
	$q->end_form(),
	$q->hr();

  # Footer comes before the audit-trail.
  page_footer($page);

  print "<h3>Audit-Trail:</h3>\n",
        $q->pre($q->escapeHTML($fields{'Audit-Trail'}));
  page_end_html($page);
}

sub get_viewpr_url
{
  my $pr = shift;
  $q->url() . "?cmd=view&database=$database&pr=$pr";
}

sub submitedit
{
  my $page = 'Edit PR Results';
  page_start_html($page);

  my $debug = 0;

  my($pr) = $q->param('pr');
  if(!$pr)
  {
    page_heading($page, 'Error');
    print "<h3>You must specify a problem report number</h3>";
    return;
  }

  my(%fields, %mailto, $adr);
  my $audittrail = '';
  my $err = '';
  my $ok = 1;

  my(%oldfields) = lockpr($pr, $user);
  LOCKED:
  {
    # Trim Responsible for compatibility.
    $oldfields{'Responsible'} = trim_responsible($oldfields{'Responsible'});

    # Merge %oldfields and CGI params to get %fields.  Not all gnats
    # fields have to be present in the CGI params; the ones which are
    # not specified default to their old values.
    %fields = %oldfields;
    foreach my $key ($q->param)
    {
      my $val = $q->param($key);
      if($key =~ /-Why/
         || ($fieldnames{$key} && ($fieldnames{$key} & $MULTILINE)))
      {
	$val = fix_multiline_val($val);
      }
      $fields{$key} = $val;
    }

    if ($debug)
    {
      print "<h3>debugging</h3><font size=1><pre>";
      foreach my $f (sort keys %fields)
      {
	printf "%-16s %s\n", $f, $q->escapeHTML($fields{$f});
      }
      print "</pre></font><hr>\n";
    }

    # TODO: fix this default; it doesn't seem right
    if($user eq "")
    {
      $user = $oldfields{'Reply-To'};
    }

    if($fields{'Last-Modified'} ne $oldfields{'Last-Modified'})
    {
      page_heading($page, 'Error');
      print "<h3>Sorry, PR $pr has been modified since you started editing it.</h3>\n",
            "Please return to the edit form, press the Reload button, ",
            "then make your edits again.\n";
      print "<pre>Last-Modified was    '$fields{'Last-Modified'}'\n";
      print "Last-Modified is now '$oldfields{'Last-Modified'}'</pre>\n";
      last LOCKED;
    }

    if($user eq "" || $fields{'Responsible'} eq "")
    {
      page_heading($page, 'Error');
      print "<h3>Responsible party is '$fields{'Responsible'}', user is '$user'!</h3>\n";
      last LOCKED;
    }

    # If X-GNATS-Notify or Reply-To changed, we need to splice the
    # change into the envelope.
    foreach ('Reply-To', 'X-GNATS-Notify')
    {
      if($fields{$_} ne $oldfields{$_})
      {
        if ($fields{'envelope'} =~ /^$_: /m)
        {
          # Replace existing header with new one.
          $fields{'envelope'} =~ s/^$_: .*$/$_: $fields{$_}/m;
        }
        else
        {
          # Insert new header at end (blank line).  Keep blank line at end.
          $fields{'envelope'} =~ s/^$/$_: $fields{$_}\n/m;
        }
      }
    }

    # Leave an Audit-Trail
    foreach (@fieldnames)
    {
      if($_ ne "Audit-Trail")
      {
	if($fields{$_} ne $oldfields{$_})
	{
          next unless ($fieldnames{$_} & $AUDITINCLUDE);
	  if($fieldnames{$_} & $MULTILINE)
	  {
            # For multitext fields, indent the values.
            my $tmp = $oldfields{$_};
            $tmp =~ s/^/    /gm;
	    $audittrail .= "$_-Changed-From:\n$tmp";
            $tmp = $fields{$_};
            $tmp =~ s/^/    /gm;
	    $audittrail .= "$_-Changed-To:\n$tmp";
	  }
          else
          {
            $audittrail .= "$_-Changed-From-To: $oldfields{$_}->$fields{$_}\n";
	  }
	  $audittrail .= "$_-Changed-By: $user\n";
	  $audittrail .= "$_-Changed-When: " . scalar(localtime()) . "\n";
	  if($fieldnames{$_} & $REASONCHANGE)
	  {
	    if($fields{"$_-Why"} =~ /^\s*$/)
	    {
              page_heading($page, 'Error') if $ok;
	      print "<h3>Field '$_' must have a reason for change</h3>",
                    "Old $_: $oldfields{$_}<br>",
                    "New $_: $fields{$_}";
	      $ok = 0;
	    }
            else
            {
              # Indent the "Why" value.
              my $tmp = $fields{"$_-Why"};
              $tmp =~ s/^/    /gm;
              $audittrail .= "$_-Changed-Why:\n" . $tmp;
            }
	  }
	}
      }
    }
    $fields{'Audit-Trail'} = $oldfields{'Audit-Trail'} . $audittrail;

    # every good let's continue
    if($ok)
    {
      my $mail_sent = 0;

      # Get list of people to notify, then add old responsible person.
      # If that person doesn't exist, don't worry about it.
      %mailto = interested_parties($pr, %fields);
      if(defined($adr = praddr($oldfields{'Responsible'})))
      {
        $mailto{$adr} = 1;
      }

      my($newpr) = unparsepr('gnatsd', %fields);
      $newpr =~ s/\r//g;
      #print $q->pre($q->escapeHTML($newpr));
      #last LOCKED; # debug

      # Submit the edits.
      client_cmd("edit $fields{'Number'}");
      client_cmd("$newpr\n.");

      # Now send mail to all concerned parties,
      # but only if there's something interesting to say.
      my($mailto);
      delete $mailto{''};
      $mailto = join(", ", sort(keys(%mailto)));
      #print pre($q->escapeHTML("mailto->$mailto<-\n"));
      #last LOCKED; # debug
      if($mailto ne "" && $audittrail ne "")
      {
        # Use email address in responsible file as From, if present.
        my $from = $responsible_address{$user} || $user;
        if(open(MAILER, "|$site_mailer"))
	{
	  print MAILER "To: $mailto\n";
	  print MAILER "From: $from\n";
	  print MAILER "Subject: Re: $fields{'Category'}/$pr\n\n";
          if ($oldfields{'Synopsis'} eq $fields{'Synopsis'})
          {
            print MAILER "Synopsis: $fields{'Synopsis'}\n\n";
          }
          else
          {
            print MAILER "Old Synopsis: $oldfields{'Synopsis'}\n";
            print MAILER "New Synopsis: $fields{'Synopsis'}\n\n";
          }
          print MAILER "$audittrail\n";
          # Print URL so that HTML-enabled mail readers can jump to the PR.
          print MAILER get_viewpr_url($pr), "\n";
          if(!close(MAILER))
	  {
            page_heading($page, 'Error');
	    print "<h3>Edit successful, but email notification failed</h3>",
                  "Bad pipe to $site_mailer";
	    last LOCKED;
	  }
          $mail_sent = 1;
	}
	else
	{
          page_heading($page, 'Error');
          print "<h3>Edit successful, but email notification failed</h3>",
                "Can't run $site_mailer";
          last LOCKED;
	}
      }
      page_heading($page, 'Edit Successful');
      print "<h3>Your changes to PR $fields{'Number'} were filed to the database.</h3>\n";
      print "The parties concerned were notified via e-mail:<br>",
            "<pre>$mailto</pre>"
            if $mail_sent;
    }
  }
  unlockpr($fields{'Number'});

  page_footer($page);
  page_end_html($page);
}

sub query_page
{
  my $page = 'Query PR';
  page_start_html($page);
  page_heading($page, 'Query Problem Reports', 1);
  print_stored_queries();
  print $q->start_form(),
	$q->submit('cmd', 'submit query'),
        "<hr>",
	"<table>",
	"<tr><td>Category:<td>",
	$q->popup_menu(-name=>'category',
		       -values=>\@category,
		       -default=>$category[0]),
	"<tr><td>Severity:<td>",
	$q->popup_menu(-name=>'severity',
	               -values=>\@severity,
		       -default=>$severity[0]),
	"<tr><td>Priority:<td>",
	$q->popup_menu(-name=>'priority',
	               -values=>\@priority,
		       -default=>$priority[0]),
	"<tr><td>Responsible:<td>",
	$q->popup_menu(-name=>'responsible',
		       -values=>\@responsible,
		       -default=>$responsible[0]),
	"<tr><td>State:<td>",
	$q->popup_menu(-name=>'state',
		       -values=>\@state,
		       -default=>$state[0]),
	"<tr><td><td>",
	$q->checkbox_group(-name=>'ignoreclosed',
	               -values=>['Ignore Closed'],
		       -defaults=>['Ignore Closed']),
	"<tr><td>Class:<td>",
	$q->popup_menu(-name=>'class',
		       -values=>\@class,
		       -default=>$class[0]),
	"<tr><td>Synopsis Search:<td>",
	$q->textfield(-name=>'synopsis',-size=>25),
	"<tr><td>Multi-line Text Search:<td>",
	$q->textfield(-name=>'multitext',-size=>25),
	"<tr><td><td>",
	$q->checkbox_group(-name=>'originatedbyme',
	               -values=>['Originated by You'],
		       -defaults=>[]),
	"<tr valign=top><td>Column Display:<td>";
  my $defaultsref = @columns ? \@columns : \@deffields;
  print $q->scrolling_list(-name=>'columns',
                           -values=>\@fields,
                           -defaults=>$defaultsref,
                           -multiple=>1,
                           -size=>5),
	"</table>",
        "<hr>",
	$q->submit('cmd', 'submit query'),
        $q->end_form();

  page_footer($page);
  page_end_html($page);
}

sub advanced_query_page
{
  my $page = 'Advanced Query';
  page_start_html($page);
  page_heading($page, 'Query Problem Reports', 1);
  print_stored_queries();
  print $q->start_form();

  my $width = 30;
  my $heading_bg = '#9fbdf9';
  my $cell_bg = '#d0d0d0';

  print $q->submit('cmd', 'submit query'),
	" or ",
	$q->reset(-name=>'reset');
  print "<hr>";
  print "<center>";

  ### Text and multitext queries

  print "<table border=1 bgcolor=$cell_bg>",
        "<caption>Search All Text</caption>",
        "<tr bgcolor=$heading_bg>",
        "<th nowrap>Search these text fields",
        "<th nowrap>using regular expression",
        "</tr>\n";
  print "<tr><td>Single-line text fields:<td>",
        $q->textfield(-name=>'text', -size=>$width),
        "</tr>\n",
        "<tr><td>Multi-line text fields:<td>",
        $q->textfield(-name=>'multitext', -size=>$width),
        "</tr>\n",
        "</table>\n";

  ### Date queries

  print "<table border=1 bgcolor=$cell_bg>",
        "<caption>Search By Date</caption>",
        "<tr bgcolor=$heading_bg>",
        "<th nowrap>Date Search",
        "<th nowrap>Example: <tt>1999-04-01 05:00 GMT</tt>",
        "</tr>\n";
  my(@date_queries) =  ('Arrived After', 'Arrived Before',
                        'Modified After', 'Modified Before',
                        'Closed After', 'Closed Before');
  push(@date_queries, 'Required After', 'Required Before')
        if $site_release_based;
  foreach (@date_queries)
  {
    my $param_name = lc($_);
    $param_name =~ s/ //;
    print "<tr><td>$_:<td>",
          $q->textfield(-name=>$param_name, -size=>$width),
          "</tr>\n";
  }
  print "</table>\n";

  ### Field queries

  print "<table border=1 bgcolor=$cell_bg>",
        "<caption>Search Individual Fields</caption>",
        "<tr bgcolor=$heading_bg>",
        "<th nowrap>Search this field",
        "<th nowrap>using regular expression, or",
        "<th nowrap>using multi-selection",
        "</tr>\n";
  foreach (@fieldnames)
  {
    my $lc_fieldname = field2param($_);
    next unless ($gnatsd_query{$lc_fieldname});

    print "<tr valign=top>";

    # 1st column is field name
    print "<td>$_:";

    # 2nd column is regexp search field
    print "<td>",
          $q->textfield(-name=>$lc_fieldname,
                        -size=>$width);
    if ($_ eq 'State')
    {
      print "<br>",
            $q->checkbox_group(-name=>'ignoreclosed',
                               -values=>['Ignore Closed'],
                               -defaults=>['Ignore Closed']),
    }

    # 3rd column is blank or scrolling multi-select list
    print "<td>";
    if ($fieldnames{$_} & $ENUM)
    {
      my $ary_ref = \@$lc_fieldname;
      my $size = scalar(@$ary_ref);
      $size = 4 if $size > 4;
      print $q->scrolling_list(-name=>$lc_fieldname,
                               -values=>$ary_ref,
                               -multiple=>1,
                               -size=>$size);
    }
    else
    {
      print "&nbsp;";
    }
    print "\n";
  }
  print	"</table>\n";

  ### Column selection

  my $defaultsref = @columns ? \@columns : \@deffields;
  print "<table border=1 bgcolor=$cell_bg>",
        "<caption>Select Columns to Display</caption>",
        "<tr valign=top><td>Display these columns:<td>",
        $q->scrolling_list(-name=>'columns',
                           -values=>\@fields,
                           -defaults=>$defaultsref,
                           -multiple=>1),
	"</table>\n";

  ### Wrapup

  print "</center>\n";
  print "<hr>",
	$q->submit('cmd', 'submit query'),
	" or ",
	$q->reset(-name=>'reset'),
	$q->end_form();
  page_footer($page);
  page_end_html($page);
}

sub submitquery
{
  my $page = 'Query Results';
  page_start_html($page);
  page_heading($page, 'Query Results', 1);
  my $debug = 0;

  my $originatedbyme = $q->param('originatedbyme');
  my $ignoreclosed   = $q->param('ignoreclosed');

  local($client_cmd_debug) = 1 if $debug;
  client_cmd("rset");
  client_cmd("orig $user") if($originatedbyme);
  client_cmd("nocl")       if($ignoreclosed);

  # Submit client_cmd for each param which specifies a query.
  my($param, $regexp, @val);
  foreach $param ($q->param())
  {
    next unless $gnatsd_query{$param};

    # Turn multiple param values into regular expression.
    @val = $q->param($param);
    $regexp = join('|', @val);

    # Discard trailing '|all', or leading '|'.
    $regexp =~ s/\|all$//;
    $regexp =~ s/^\|//;

    # If there's still a query here, make it.
    client_cmd("$gnatsd_query{$param} $regexp")
          if($regexp && $regexp ne 'all');
  }

  my(@query_results) = client_cmd("sql2");

  display_query_results(@query_results);
  page_footer($page);
  page_end_html($page);
}

# by_field -
#     Sort routine called by display_query_results.
#
#     Assumes $sortby is set by caller.
#
sub by_field
{
  my($val);
  if (!$sortby || $sortby eq 'PR')
  {
    $val = $a->[0] <=> $b->[0];
  }
  elsif ($sortby eq 'Category')
  {
    $val = $a->[1] cmp $b->[1];
  }
  elsif ($sortby eq 'Confidential')
  {
    $val = $a->[3] cmp $b->[3];
  }
  elsif ($sortby eq 'Severity')
  {
    # sort by Severity then Priority then Class
    $val = $a->[4] <=> $b->[4]
                   ||
           $a->[5] <=> $b->[5]
                   ||
           $a->[8] <=> $b->[8]
                   ;
  }
  elsif ($sortby eq 'Priority')
  {
    # sort by Priority then Severity then Class
    $val = $a->[5] <=> $b->[5]
                   ||
           $a->[4] <=> $b->[4]
                   ||
           $a->[8] <=> $b->[8]
                   ;
  }
  elsif ($sortby eq 'Responsible')
  {
    $val = $a->[6] cmp $b->[6];
  }
  elsif ($sortby eq 'State')
  {
    $val = $a->[7] <=> $b->[7];
  }
  elsif ($sortby eq 'Class')
  {
    $val = $a->[8] <=> $b->[8];
  }
  elsif ($sortby eq 'Submitter-Id')
  {
    $val = $a->[9] cmp $b->[9];
  }
  elsif ($sortby eq 'Release')
  {
    $val = $a->[12] cmp $b->[12];
  }
  else
  {
    $val = $a->[0] <=> $b->[0];
  }
  $val;
}

# nonempty -
#     Turn empty strings into "&nbsp;" so that Netscape tables won't
#     look funny.
#
sub nonempty
{
  my $str = shift;
  $str = '&nbsp;' if !$str;
  $str;
}

# field2param -
#     Convert gnats field name into parameter name, e.g.
#     "Submitter-Id" => "submitter_id".  It's done this crazy way for
#     compatibility with queries stored by gnatsweb 2.1.
#
sub field2param
{
  my $name = shift;
  $name =~ s/-/_/g;
  $name = lc($name);
}

# param2field -
#     Convert parameter name into gnats field name, e.g.
#     "submitter_id" => "Submitter-Id".  It's done this crazy way for
#     compatibility with queries stored by gnatsweb 2.1.
#
sub param2field
{
  my $name = shift;
  my @words = split(/_/, $name);
  map { $_ = ucfirst($_); } @words;
  $name = join('-', @words);
}

# display_query_results -
#     Display the query results, and the "store query" form.
sub display_query_results
{
  my(@query_results) = @_;
  my(@fields) = $q->param('columns');
  my($field, %fields);

  my $num_matches = scalar(@query_results);
  my $heading = sprintf("%s %s found",
                        $num_matches ? $num_matches : "No",
                        ($num_matches == 1) ? "match" : "matches");
  print $q->h2($heading);

  # Sort @query_results according to the rules in by_field().
  # Using the "map, sort" idiom allows us to perform the expensive
  # split() only once per item, as opposed to during every comparison.
  # Note that $sortby must be 'local'...it's used in by_field().
  local($sortby) = $q->param('sortby');
  my(@sortable) = ('PR','Category','Confidential',
                   'Severity','Priority','Responsible',
                   'State','Class','Release','Submitter-Id');
  my(@presplit_prs) = map { [ (split /\|/) ] } @query_results;
  my(@sorted_prs) = sort by_field @presplit_prs;

  print $q->start_form(),
	$q->hidden(name=>'cmd', -value=>'view', -override=>1),
	"<table border=1>";

  # Print table header which allows sorting by some columns.
  # While printing the headers, temporarily override the 'sortby' param
  # so that self_url() works right.
  print "<tr>";
  for $field ('PR', @fields)
  {
    $ufield = param2field($field);
    if (grep(/$ufield/, @sortable))
    {
      $q->param(-name=>'sortby', -value=>$ufield);
      my $href = $q->self_url();
      # 6/25/99 kenstir: CEL claims this avoids a problem w/ apache+mod_perl.
      $href =~ s/^[^?]*\?/$sn\?/; #CEL
      print "<th><a href=\"$href\">$ufield</a>";
    }
    else
    {
      print "<th>$ufield";
    }
    $fields{$field}++;
  }
  # Reset param 'sortby' to its original value, so that 'store query' works.
  $q->param(-name=>'sortby', -value=>$sortby);
  print "</tr>";

  # Print the PR's.
  foreach (@sorted_prs)
  {
    print "<tr valign=top>";

    my($id, $cat, $syn, $conf, $sev,
       $pri, $resp, $state, $class, $sub,
       $arrival, $orig, $release, $lastmoddate, $closeddate,
       $target, $keywords, $daterequired) = @{$_};
    print "<td nowrap><a href=\"$sn?cmd=view&pr=$id\">$id</a>"; 
    print "<td nowrap>$cat"                      if $fields{'category'};
    print "<td nowrap>$conf"                     if $fields{'confidential'};
    print "<td nowrap>$state[$state]"            if $fields{'state'};
    print "<td nowrap>$class[$class]"            if $fields{'class'};
    print "<td nowrap>$severity[$sev]"           if $fields{'severity'};
    print "<td nowrap>$priority[$pri]"           if $fields{'priority'};
    print "<td nowrap>", nonempty($release)      if $fields{'release'};
    print "<td nowrap>", nonempty($target)       if($site_release_based
                                                    && $fields{'target'});
    print "<td>", nonempty($keywords)            if($site_release_based
                                                    && $fields{'keywords'});
    print "<td nowrap>$resp"                     if $fields{'responsible'};
    print "<td nowrap>", nonempty($sub)          if $fields{'submitter_id'};
    print "<td nowrap>", nonempty($orig)         if $fields{'originator'};
    print "<td nowrap>$arrival"                  if $fields{'arrival_date'};
    print "<td nowrap>", nonempty($daterequired) if($site_release_based
                                                    && $fields{'date_required'});
    print "<td nowrap>", nonempty($lastmoddate)  if $fields{'last_modified'};
    print "<td nowrap>", nonempty($closeddate)   if $fields{'closed_date'};
    print "<td>$syn"                             if $fields{'synopsis'};
    print "</tr>\n";
  }
  print "</table>",
        $q->end_form();

  # Allow the user to store this query.  Need to repeat params as hidden
  # fields so they are available to the 'store query' handler.
  print $q->start_form();
  foreach ($q->param())
  {
    # Ignore certain params.
    next if /^(cmd|queryname)$/;
    print $q->hidden($_);
  }
  print "<table>",
        "<tr>",
        "<td>Remember this query as:",
        "<td>",
        $q->textfield(-name=>'queryname', -size=>25),
        "<td>";
  # Note: include hidden 'cmd' so user can simply press Enter w/o clicking.
  print $q->hidden(-name=>'cmd', -value=>'store query', -override=>1),
        $q->submit('cmd', 'store query'),
        "</table>",
        $q->end_form();
}

# store_query -
#     Save the current query in a cookie.
#
#     Queries are stored as individual cookies named
#     'gnatsweb-query-$queryname'.
#
sub store_query
{
  my $debug = 0;
  my $queryname = $q->param('queryname');

  # Don't save certain params.
  $q->delete('cmd');
  my $query_string = $q->query_string();

  # Have to generate the cookie before printing the header.
  my $new_cookie = $q->cookie(-name => "gnatsweb-query-$queryname",
                              -value => $query_string,
                              -expires => '+10y');
  print $q->header(-cookie => $new_cookie);

  # Now print the page.
  my $page = 'Query Saved';
  page_start_html($page);
  page_heading($page, 'Query Saved');
  print "<h2>debugging</h2><pre>",
        "query_string: $query_string",
        "cookie: $new_cookie\n",
        "</pre><hr>\n"
        if $debug;
  print "<p>Your query has been saved.  It will be available ",
        "the next time you reload the Query page.";
  page_footer($page);
  page_end_html($page);
}

# print_stored_queries -
#     Retrieve any stored queries and print out a short form allowing
#     the submission of these queries.
#
#     Queries are stored as individual cookies named
#     'gnatsweb-query-$queryname'.
#
# side effects:
#     Sets global %stored_queries.
#
sub print_stored_queries
{
  %stored_queries = ();
  foreach my $cookie ($q->cookie())
  {
    if ($cookie =~ /gnatsweb-query-(.*)/)
    {
      $stored_queries{$1} = $q->cookie($cookie);
    }
  }
  if (%stored_queries)
  {
    print $q->start_form(),
          "<table cellspacing=0 cellpadding=0 border=0>",
          "<tr valign=top><td>",
          $q->submit('cmd', 'submit stored query'),
          "<td>&nbsp;<td>",
          $q->popup_menu(-name=>'queryname',
                         -values=>[ sort(keys %stored_queries) ]),
          "</tr></table>",
          $q->end_form();
  }
}

# submit_stored_query -
#     Submit the query named in the param 'queryname'.
#
#     Queries are stored as individual cookies named
#     'gnatsweb-query-$queryname'.
#
sub submit_stored_query
{
  my $debug = 0;
  my $queryname = $q->param('queryname');
  my $query_string;
  my $err = '';
  if (!$queryname)
  {
    $err = "Internal error: no 'queryname' parameter";
  }
  elsif (!($query_string = $q->cookie("gnatsweb-query-$queryname")))
  {
    $err = "No such named query: $queryname";
  }
  if ($err)
  {
    print $q->header(),
          $q->start_html('Error'),
          $q->h3($err),
          $q->end_html();
  }
  else
  {
    my $query_url = $q->script_name() . '?cmd=' . $q->escape('submit query')
          . '&' . $query_string;
    if ($debug)
    {
      print $q->header(),
            $q->start_html(),
            $q->pre("debug: query_url: $query_url\n");
    }
    else
    {
      print $q->redirect($query_url);
    }
  }
}

sub help_page
{
  my $page = 'Help';
  page_start_html($page);
  page_heading($page, 'Help', 1);
  print p('Welcome to our problem report database. ',
          'You\'ll notice that here we call them "problem reports" ',
          'or "PR\'s", not "bugs".');
  print p('This web interface is called "gnatsweb". ',
          'The database system itself is called "gnats".',
          'You may want to peruse ',
          a({-href=>"$gnats_info_top?(gnats)"}, 'the gnats manual'),
          'to read about bug lifecycles and the like, ',
          'but then again, you may not.');
  page_footer($page);
  page_end_html($page);
}

sub one_line_form
{
  my($label, @form_body) = @_;
  my $valign = 'baseline';
  print $q->Tr({-valign=>$valign},
               $q->td($q->b($label)),
               $q->td(start_form(), @form_body, end_form()));
}

# can_edit -
#     Return true if the user has edit priviledges or better.
#
sub can_edit
{
  return ($access_level =~ /edit|admin/);
}

sub main_page
{
  my $page = 'Main';
  page_start_html($page);
  page_heading($page, 'Main Page', 1);
  print '<p><table>';

  one_line_form('Create Problem Report:',
                submit('cmd', 'create'));
  # Only include Edit action if user is allowed to edit PRs.
  # Note: include hidden 'cmd' so user can simply press Enter w/o clicking.
  if (can_edit())
  {
    one_line_form('Edit Problem Report:',
		  hidden(-name=>'cmd', -value=>'edit', -override=>1),
		  submit('cmd', 'edit'),
		  '#',
		  textfield(-size=>6, -name=>'pr'));
  }
  one_line_form('View Problem Report:',
                hidden(-name=>'cmd', -value=>'view', -override=>1),
                submit('cmd', 'view'),
                '#',
                textfield(-size=>6, -name=>'pr'));
  one_line_form('Query Problem Reports:',
                submit('cmd', 'query'));
  one_line_form('Advanced Query:',
                submit('cmd', 'advanced query'));
  one_line_form('Login again:',
                submit('cmd', 'login again'));
  one_line_form('Get Help:',
                submit('cmd', 'help'));
  print '</table>';
  page_footer($page);
  print '<hr><small>',
        "Gnatsweb $VERSION, brought to you by<br>",
        $q->escapeHTML(
                       'Matt Gerassimoff <mg@digalogsys.com> ' .
                       'and Kenneth H. Cox <kenstir@senteinc.com>.'),
        '</small>';
  page_end_html($page);
}

# cb -
#
#     Calls site_callback subroutine if defined.
#
# usage:
#     $something = cb($reason, @args) || 'default_value';
#     # -or-
#     $something = cb($reason, @args)
#     $something = 'default_value' unless defined($something);
#
# arguments:
#     $reason - reason for the call.  Each reason is unique.
#     @args   - additional parameters may be provided in @args.
#
# returns:
#     undef if &site_callback is not defined,
#     else value returned by &site_callback.
#
sub cb
{
  my($reason, @args) = @_;
  my $val = undef;
  if (defined &site_callback)
  {
    $val = site_callback($reason, @args);
  }
  $val;
}

# page_start_html -
#
#     Print the HTML which starts off each page (<html><head>...</head>).  
#
#     By default, print a banner containing $site_banner_text, followed
#     by the given page $title.
#
#     The starting HTML can be overridden by &site_callback.
#
#     Supports debugging.
#
# arguments:
#     $title - title of page
#
sub page_start_html
{
  my $title = shift;
  my $debug = 0;

  # Allow site callback to override html.
  my $html = cb('page_start_html', $title);
  if ($html)
  {
    print $html;
    return;
  }

  print $q->start_html(-title=>"$title - $site_banner_text",
                       -bgcolor=>'#ffffff');

  # Add the page banner.  This banner is a string slammed to the right
  # of a 100% width table.  The data is a link back to the main page.
  #
  # Note that the banner uses inline style, rather than a GIF; this
  # makes installation easier by eliminating the need to install GIFs
  # into a separate directory.  At least for Apache, you can't serve
  # GIFs out of your CGI directory.
  #
  # Danger!  Don't use double quotes inside $style; that will confuse
  # Netscape 4.5.  Use single quotes if needed.  Don't use multi-line
  # comments; they confuse Netscape 4.5.
  my $browser = $ENV{'HTTP_USER_AGENT'};
  my $style;
  if ($browser =~ /Mozilla.*X11/)
  {
    # Netscape Unix
    # monospace/36pt works well.
    $style = <<END_OF_STYLE;
      color:       white;
      font-family: monospace;
      /*font-family: lucidatypewriter, monospace;*/
      font-size:   36pt;
      text-decoration: none;
END_OF_STYLE
  }
  else
  {
    # monospace/28pt/bold works well in NS/Win95 (uses 'Courier New').
    $style = <<END_OF_STYLE;
      color:       white;
      font-family: 'Courier New', monospace;
      font-size:   28pt;
      font-weight: 600;
      text-decoration: none;
END_OF_STYLE
  }
  my($row, $banner);
  $row = $q->Tr($q->td({-align=>'right'},
                       $q->a({-style=>$style, -href=>$sn},
                             ' ', $site_banner_text, ' ')));
  $banner = $q->table({-bgcolor=>'#000000', -width=>'100%',
                       -border=>0, -cellpadding=>0, -cellspacing=>0},
                      $row);
  print $banner;

  # debugging
  if ($debug)
  {
    print "<h3>debugging params</h3><font size=1><pre>";
    my($param,@val);
    foreach $param (sort $q->param())
    {
      @val = $q->param($param);
      printf "%-12s %s\n", $param, $q->escapeHTML(join(' ', @val));
    }
    print "</pre></font><hr>\n";
  }
}

# page_heading -
#
#     Print the HTML which starts off a page.  Basically a fancy <h1>
#     plus user + database names.
#
sub page_heading
{
  my($title, $heading, $display_user_info) = @_;

  # Allow site callback to override html.
  my $html = cb('page_heading', $title, $heading);
  if ($html)
  {
    print $html;
    return;
  }

  my $leftcol = $heading ? $heading : '&nbsp;';
  my $rightcol;

  if ($user && defined($display_user_info))
  {
    $rightcol= "<tt><small>User: $user<br>" .
               "Database: $database<br>" .
               "Access: $access_level</tt></small>";
  }
  else
  {
    $rightcol = '&nbsp;';
  }

  print $q->table($q->Tr($q->td({-nowrap=>1}, $q->font({-size=>'+3'},
                                                       $leftcol)),
                         # this column serves as empty expandable filler
                         $q->td({-width=>'100%'}, '&nbsp;'),
                         $q->td({-nowrap=>1}, $rightcol)));
}

# page_footer -
#
#     Allow the site_callback to take control before the end of the
#     page.
#
sub page_footer
{
  my $title = shift;

  my $html = cb('page_footer', $title);
  print $html if ($html);
}

# page_end_html -
#
#     Print the HTML which ends a page.  Allow the site_callback to
#     take control here too.
#
sub page_end_html
{
  my $title = shift;

  # Allow site callback to override html.
  my $html = cb('page_end_html', $title);
  if ($html)
  {
    print $html;
    return;
  }

  print $q->end_html();
}

# fix_multiline_val -
#     Modify text of multitext field so that it contains \n separators
#     (not \r\n or \n as some platforms use), and so that it has a \n
#     at the end.
#
sub fix_multiline_val
{
  my $val = shift;
  $val =~ s/\r\n?/\n/g;
  $val .= "\n" unless $val =~ /\n$/;
  $val;
}

# parse_config -
#     Parse the config file, storing the name/value pairs in the global
#     hash %config.
sub parse_config
{
  my(@lines) = @_;

  %config = ();

  # Default value for GNATS_ADDR is 'bugs'.
  $config{'GNATS_ADDR'} = 'bugs';

  # Note that the values may be quoted, as the config file uses
  # Bourne-shell syntax.
  foreach $_ (@lines)
  {
    if (/(\S+)\s*=\s*['"]?([^'"]*)['"]?/)
    {
      $config{$1} = $2;
    }
  }
}

# parse_categories -
#     Parse the categories file.
sub parse_categories
{
  my(@lines) = @_;

  @category = ("all");
  %category_notify = ();

  foreach $_ (sort @lines)
  {
    my($cat, $desc, $resp, $notify) = split(/:/);
    # Exclude administrative category 'pending'.
    next if($cat eq 'pending');
    push(@category, $cat);
    $category_notify{$cat} = $notify;
  }
}

# parse_submitters -
#     Parse the submitters file.
sub parse_submitters
{
  my(@lines) = @_;

  @submitter_id = ("all");
  %submitter_contact = ();
  %submitter_notify = ();

  foreach $_ (sort @lines)
  {
    my($submitter, $full_name, $type, $response_time, $contact, $notify)
          = split(/:/);
    push(@submitter_id, $submitter);
    $submitter_contact{$submitter} = $contact;
    $submitter_notify{$submitter} = $notify;
  }
}

# parse_responsible -
#     Parse the responsible file.
sub parse_responsible
{
  my(@lines) = @_;

  @responsible = ("all");
  %responsible_fullname = ();
  %responsible_address = ();

  foreach $_ (sort @lines)
  {
    my($person, $fullname, $address) = split(/:/);
    push(@responsible, $person);
    $responsible_fullname{$person} = $fullname;
    $responsible_address{$person} = $address || $person;
  }
}

sub initialize
{
  my $regression_testing = shift;

  @severity = ("all", "critical", "serious", "non-critical");
  @priority = ("all", "high", "medium", "low");
  @confidential = ("all", "no", "yes");

  # @fields - param names of columns displayable in query results
  # @deffields - default displayed columns
  @deffields = ("category", "state", "responsible", "synopsis");
  @fields = ("category", "confidential", "state", "class",
             "severity", "priority",
             "release", "target", "responsible", "submitter_id", "originator",
             "arrival_date", "date_required",
             "last_modified", "closed_date", "synopsis");

  # @fieldnames - fields appear in the standard order, defined by pr.h
  @fieldnames = (
    "Number",
    "Category",
    "Synopsis",
    "Confidential",
    "Severity",
    "Priority",
    "Responsible",
    "State",
    "Target",
    "Keywords",
    "Date-Required",
    "Class",
    "Submitter-Id",
    "Arrival-Date",
    "Closed-Date",
    "Last-Modified",
    "Originator",
    "Release",
    "Organization",
    "Environment",
    "Description",
    "How-To-Repeat",
    "Fix",
    "Release-Note",
    "Audit-Trail",
    "Unformatted",
  );

  # %fieldnames maps the field name to a flag value composed of bits.
  # See $MULTILINE above for bit definitions.
  %fieldnames = (
    "Number"        => $SENDEXCLUDE | $EDITEXCLUDE,
    "Category"      => $ENUM,
    "Synopsis"      => 0,
    "Confidential"  => $ENUM,
    "Severity"      => $ENUM,
    "Priority"      => $ENUM,
    "Responsible"   => $ENUM | $REASONCHANGE | $SENDEXCLUDE | $AUDITINCLUDE,
    "State"         => $ENUM | $REASONCHANGE | $SENDEXCLUDE | $AUDITINCLUDE,
    "Target"        => 0,
    "Keywords"      => 0,
    "Date-Required" => 0,
    "Class"         => $ENUM,
    "Submitter-Id"  => $ENUM | $EDITEXCLUDE,
    "Arrival-Date"  => $SENDEXCLUDE | $EDITEXCLUDE,
    "Closed-Date"   => $SENDEXCLUDE | $EDITEXCLUDE,
    "Last-Modified" => $SENDEXCLUDE | $EDITEXCLUDE,
    "Originator"    => $EDITEXCLUDE,
    "Release"       => 0,
    "Organization"  => $MULTILINE | $SENDEXCLUDE | $EDITEXCLUDE, # => $MULTILINE
    "Environment"   => $MULTILINE,
    "Description"   => $MULTILINE,
    "How-To-Repeat" => $MULTILINE,
    "Fix"           => $MULTILINE,
    "Release-Note"  => $MULTILINE | $SENDEXCLUDE,
    "Audit-Trail"   => $MULTILINE | $SENDEXCLUDE | $EDITEXCLUDE,
    "Unformatted"   => $MULTILINE | $SENDEXCLUDE | $EDITEXCLUDE,
  );

  # gnatsd query commands: maps param name to gnatsd command
  %gnatsd_query = (
    "category"        => 'catg',
    "synopsis"        => 'synp',
    "confidential"    => 'conf',
    "severity"        => 'svty',
    "priority"        => 'prio',
    "responsible"     => 'resp',
    "state"           => 'stat',
    "class"           => 'clss',
    "submitter_id"    => 'subm',
    "originator"      => 'orig',
    "release"         => 'rlse',
    "text"            => 'text',
    "multitext"       => 'mtxt',
    "arrivedbefore"   => 'abfr',
    "arrivedafter"    => 'araf',
    "modifiedbefore"  => 'mbfr',
    "modifiedafter"   => 'maft',
    "closedbefore"    => 'cbfr',
    "closedafter"     => 'caft',
    "target"	      => 'qrtr',
    "keywords"	      => 'keyw',
    "requiredbefore"  => 'bfor',
    "requiredafter"   => 'aftr',
  );

  # clear out some unused fields if not used
  if (!$site_release_based)
  {
    @fields = grep(!/target|keywords|date_required/, @fields);
    @fieldnames = grep(!/Target|Keywords|Date-Required/, @fieldnames);
  }

  my(@lines);
  my $response;

  # Get gnatsd version from initial server connection text.
  ($response) = client_init();
  $GNATS_VERS = 999.0;
  if ($response =~ /GNATS server (.*) ready/)
  {
    $GNATS_VERS = $1;
  }

  # Suppress fatal exit while issuing CHDB and USER commands.  Otherwise
  # an error in the $user or $database cookie values can cause a user to
  # get in a bad state.
  LOGIN:
  {
    local($suppress_client_exit) = 1
          unless $regression_testing;

    # Issue CHDB command; revert to login page if it fails.
    ($response) = client_cmd("chdb $database");
    if (!$response)
    {
      login();
      exit();
    }

    # Get user permission level from USER command.  Revert to the
    # login page if the command fails.
    ($response) = client_cmd("user $user $password");
    if (!$response)
    {
      login();
      exit();
    }
    $access_level = 'edit';
    if ($response =~ /User access level set to (\w*)/)
    {
      $access_level = $1;
    }
  }

  # Get some enumerated lists
  my($x, $dummy);
  @state = ("all");
  foreach $_ (client_cmd("lsta"))
  {
    ($x, $dummy) = split(/:/);
    push(@state, $x);
  }
  @class = ("all");
  foreach $_ (client_cmd("lcla"))
  {
    ($x, $dummy) = split(/:/);
    push(@class, $x);
  }

  # List various gnats-adm files, and parse their contents for data we
  # will need later.  Each parse subroutine stashes information away in
  # its own global vars.  The call to client_cmd() happens here to
  # enable regression testing of the parse subs using fixed files.
  @lines = client_cmd("lcfg");
  parse_config(@lines);
  @lines = client_cmd("lcat");
  parse_categories(@lines);
  @lines = client_cmd("lsub");
  parse_submitters(@lines);
  @lines = client_cmd("lres");
  parse_responsible(@lines);

  # Now that everything's all set up, let the site_callback have at it.
  # It's return value doesn't matter, but here it can muck with our defaults.
  cb('initialize');
}

# trim_responsible -
#     Trim the value of the Responsible field to get a
#     valid responsible person.  This exists here, and in gnats itself
#     (modify_pr(), check_pr(), gnats(), append_report()), for
#     compatibility with old databases, which had 'person (Full Name)'
#     in the Responsible field.
sub trim_responsible {
  my $resp = shift;
  $resp =~ s/ .*//;
  $resp;
}

# fix_email_addrs -
#     Trim email addresses as they appear in an email From or Reply-To
#     header into a comma separated list of just the addresses.
#
#     Delete everything inside ()'s and outside <>'s, inclusive.
#
sub fix_email_addrs
{
  my $addrs = shift;
  my @addrs = split(/,/, $addrs);
  my @trimmed_addrs;
  my $addr;
  foreach $addr (@addrs)
  {
    $addr =~ s/\(.*\)//;
    $addr =~ s/.*<(.*)>.*/$1/;
    $addr =~ s/^\s+//;
    $addr =~ s/\s+$//;
    push(@trimmed_addrs, $addr);
  }
  $addrs = join(', ', @trimmed_addrs);
  $addrs;
}

sub parsepr
{
  my($hdrmulti) = "envelope";
  my(%fields);
  foreach (@_)
  {
    chomp($_);
    $_ .= "\n";
    if(!/^([>\w\-]+):\s*(.*)\s*$/)
    {
      if($hdrmulti ne "")
      {
        $fields{$hdrmulti} .= $_;
      }
      next;
    }
    local($hdr, $arg, $ghdr) = ($1, $2, "*not valid*");
    if($hdr =~ /^>(.*)$/)
    {
      $ghdr = $1;
    }
    if(exists($fieldnames{$ghdr}))
    {
      if($fieldnames{$ghdr} & $MULTILINE)
      {
        $hdrmulti = $ghdr;
	$fields{$ghdr} = "";
      }
      else
      {
        $hdrmulti = "";
        $fields{$ghdr} = $arg;
      }
    }
    elsif($hdrmulti ne "")
    {
      $fields{$hdrmulti} .= $_;
    }

    # Grab a few fields out of the envelope as it flies by
    if($hdr eq "Reply-To" || $hdr eq "From" || $hdr eq "X-GNATS-Notify")
    {
      $arg = fix_email_addrs($arg);
      $fields{$hdr} = $arg;
      #print "storing, hdr = $hdr, arg = $arg\n";
    }
  }

  # 5/8/99 kenstir: To get the reporter's email address, only
  # $fields{'Reply-to'} is consulted.  Initialized it from the 'From'
  # header if it's not set, then discard the 'From' header.
  $fields{'Reply-To'} = $fields{'Reply-To'} || $fields{'From'};
  delete $fields{'From'};

  # 3/30/99 kenstir: For some reason Unformatted always ends up with an
  # extra newline here.
  $fields{'Unformatted'} =~ s/\n$//m;

  return %fields;
}

# unparsepr -
#     Turn PR fields hash into a multi-line string.
#
#     The $purpose arg controls how things are done.  The possible values
#     are:
#         'send'    - PR will be submitted as a new PR via email
#         'gntasd'  - PR will be filed using gnatsd; proper '.' escaping done
#         'test'    - we're being called from the regression tests
sub unparsepr
{
  my($purpose, %fields) = @_;
  my($tmp, $text);
  $text = $fields{'envelope'};
  foreach (@fieldnames)
  {
    next if($purpose eq "send" && $fieldnames{$_} & $SENDEXCLUDE);
    if($fieldnames{$_} & $MULTILINE)
    {
      # Lines which begin with a '.' need to be escaped by another '.'
      # if we're feeding it to gnatsd.
      $tmp = $fields{$_};
      $tmp =~ s/^[.]/../gm
            if ($purpose eq 'gnatsd');
      $text .= sprintf(">$_:\n%s", $tmp);
    }
    else
    {
      # Format string derived from gnats/pr.c.
      $text .= sprintf("%-16s %s\n", ">$_:", $fields{$_});
    }
  }
  return $text;
}

sub lockpr
{
  my($pr, $user) = @_;
  #print "<pre>locking $pr $user\n</pre>";
  return parsepr(client_cmd("lock $pr $user"));
}

sub unlockpr
{
  my($pr) = @_;
  #print "<pre>unlocking $pr\n</pre>";
  client_cmd("unlk $pr");
}

sub readpr
{
  my($pr) = @_;

  return parsepr(client_cmd("full $pr"));
}

# interested_parties -
#     Get list of parties to notify about a PR change.
#
#     Returns hash in array context; string of email addrs otherwise.
sub interested_parties
{
  my($pr, %fields) = @_;

  # Gnats 3.110 has some problems in MLPR --
  # * it includes the category's responsible person (even if that person
  #   is not responsible for this PR)
  # * it does not include the PR's responsible person
  # * it does not include the Reply-To or From
  #
  # So for now, don't use it.  However, for versions after 3.110 my
  # patch to the MLPR command should be there and this can be fixed.

  my(@people);
  my $person;

  ## Get list from MLPR command.
  #@people = client_cmd("mlpr $pr");
  # Ignore intro message
  #@people = grep(!/Addresses to notify/, @people);

  # Get list of people by constructing it ourselves.
  @people = ();
  foreach $person ($fields{'Reply-To'},
                   $fields{'Responsible'},
                   $fields{'X-GNATS-Notify'},
                   $category_notify{$fields{'Category'}},
                   $submitter_contact{$fields{'Submitter-Id'}},
                   $submitter_notify{$fields{'Submitter-Id'}})
  {
    push(@people, $person) if $person;
  }

  # Expand any unexpanded addresses, and build up the %addrs hash.
  my(%addrs) = ();
  my $addr;
  foreach $person (@people)
  {
    $addr = praddr($person) || $person;
    $addrs{$addr} = 1;
  }
  return wantarray ? %addrs : join(', ', keys(%addrs));
}

# praddr -
#     Return email address of responsible person, or undef if not found.
sub praddr
{
  my $person = shift;
  # Done this way to avoid -w warning
  my $addr = exists($responsible_address{$person})
        ? $responsible_address{$person} : undef;
}

sub login
{
  my $page = 'Login';
  page_start_html($page);
  page_heading($page, 'Login');

  client_init();
  my(@dbs) = client_cmd("dbla");
  print $q->start_form(),
        "<p>Use username '<b>guest</b>' and password '<b>guest</b>' for read-only and bug reporting access.",
        "<table>",
        "<tr><td>User Name:<td>",
        $q->textfield(-name=>'user',
                      -size=>15,
		      -default=>$user),
        "<tr><td>Password:<td>",
        $q->password_field(-name=>'password',
                           -value=>$password,
                           -size=>15,
                           -maxlength=>20),
	"<tr><td>Database:<td>",
	$q->popup_menu(-name=>'database',
	               -values=>\@dbs,
                       -default=>$database),
        "</table>",
        $q->submit('cmd','login'),
        $q->end_form();
  page_footer($page);
  page_end_html($page);
}

#
# MAIN starts here:
#
# 3/18/99 kenstir: moved code inside gnats_main so that this code is
# callable from gnatsweb.
sub main
{
  # Load gnatsweb-site.pl if present.  Die if there are errors;
  # otherwise the person who wrote gnatsweb-site.pl will never know it.
  do './gnatsweb-site.pl' if (-e './gnatsweb-site.pl');
  die $@ if $@;

  $q = new CGI;
  $sn = $q->script_name;
  $cmd = $q->param('cmd') || ''; # avoid perl -w warning

  ### Cookie-related code must happen before we print the HTML header.

  # Upon a 'store query', create + save a new cookie containing the
  # query values.
  if($cmd eq 'store query')
  {
    store_query();
    exit();
  }

  # If running a stored query, redirect the user immediately to the URL.
  if($cmd eq 'submit stored query')
  {
    submit_stored_query();
    exit();
  }

  # Print all our cookies
  #$i = 0;
  #foreach my $y ($q->cookie())
  #{
  #  @c = $q->cookie($y);
  #  warn "debug 0: $y: @c:\n";
  #  $i += length($y);
  #}
  #@c = $q->raw_cookie();
  #warn "debug 0.5: @c:\n";
  #warn "debug 0.5: total size of raw cookies: ", length("@c"), "\n";

  # Retrieve the gnatsweb cookie sent by the browser.
  %cookie = $q->cookie('gnatsweb');
  $user     = $cookie{'user'};
  $password = $cookie{'password'};
  $database = $cookie{'database'};
  $email    = $cookie{'email'};
  $cc       = $cookie{'cc'};
  $submitter_id = $cookie{'Submitter-Id'};
  $originator   = $cookie{'Originator'};
  @columns      = defined($cookie{'columns'})
        ? split(' ', $cookie{'columns'}) : ();
  #foreach $key (sort keys %cookie) {warn "debug 1: $key = $cookie{$key}\n";}

  # Upon login, store user/password/database in the gnatsweb cookie.
  if($cmd eq 'login')
  {
    $cookie{'user'}     = $user     = $q->param('user');
    $cookie{'password'} = $password = $q->param('password');
    $cookie{'database'} = $database = $q->param('database');
  }

  # Upon a new PR submission, store email addresses and select PR
  # fields in the gnatsweb cookie.  This facilitates entering bugs the
  # next time.
  if($cmd eq 'submit')
  {
    $cookie{'email'}          = $email        = $q->param('email');
    $cookie{'cc'}             = $cc           = $q->param('cc');
    $cookie{'Submitter-Id'}   = $submitter_id = $q->param('Submitter-Id');
    $cookie{'Originator'}     = $originator   = $q->param('Originator');
    #$cookie{'Category'}    = $Category    = $q->param('Category');
    #$cookie{'Release'}     = $Release     = $q->param('Release');
    #$cookie{'Environment'} = $Environment = $q->param('Environment');
    #foreach $key (sort keys %cookie) {warn "debug 2: $key = $cookie{$key}\n";}
  }

  # Upon a 'submit query', store column display list in the cookie.
  if($cmd eq 'submit query')
  {
    @columns = $q->param('columns');
    $cookie{'columns'} = join(' ', @columns);
  }

  # Refresh the gnatsweb cookie, even if it hasn't been modified, so
  # that it doesn't expire.
  $new_cookie = $q->cookie(-name => 'gnatsweb', 
                           -value => \%cookie,
                           -expires => '+1y');
  #warn "debug 3: new_cookie = $new_cookie\n";

  # Serve the cookie.
  print $q->header(-cookie=>$new_cookie);

  ### Now determine what page the user wants to see.

  # Return to the login page only if we haven't been there
  # already, or if the user specifically requested to login again.
  if($cmd eq 'login again' || !$user || !$password || !$database)
  {
    login();
    exit();
  }

  initialize();

  if($cmd eq 'create')
  {
    sendpr();
  }
  elsif($cmd eq 'submit')
  {
    submitnewpr();
  }
  elsif($cmd eq 'view')
  {
    view(0);
  }
  elsif($cmd eq 'view audit-trail')
  {
    view(1);
  }
  elsif($cmd eq 'edit')
  {
    edit();
  }
  elsif($cmd eq 'submit edit')
  {
    submitedit();
  }
  elsif($cmd eq 'query')
  {
    query_page();
  }
  elsif($cmd eq 'advanced query')
  {
    advanced_query_page();
  }
  elsif($cmd eq 'submit query')
  {
    submitquery();
  }
  elsif($cmd eq 'store query')
  {
    store_query();
  }
  elsif($cmd eq 'help')
  {
    help_page();
  }
  else
  {
    main_page();
  }

  client_exit();
}

# To make this code callable from another source file, set $suppress_main.
$suppress_main ||= 0;
main() unless $suppress_main;

# Emacs stuff -
#
# Local Variables:
# perl-indent-level:2
# perl-continued-brace-offset:-6
# perl-continued-statement-offset:6
# End:
