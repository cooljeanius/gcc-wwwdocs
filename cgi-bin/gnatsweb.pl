#!/usr/bin/perl -w
#
# Gnatsweb - web front-end to gnats
#
# Copyright 1998-1999 - Matt Gerassimoff
# and Ken Cox <kenstir@senteinc.com>
#
# $Id: gnatsweb.pl,v 1.135 1999/12/01 04:31:47 kenstir Exp $
#

#-----------------------------------------------------------------------------
# Site-specific customization -
#
#     WE STRONGLY SUGGEST you don't edit these variables here, but instead
#     put them in a file called 'gnatsweb-site.pl' in the same directory.
#     That way, when a new version of gnatsweb is released, you won't
#     need to edit them again.
#

# Info about your gnats host.
$site_gnats_host = 'localhost';
$site_gnats_port = 1529;

#GCC-LOCAL begin.
$submitter_id = 'net';
#GCC-LOCAL end.

# Set to true if you compiled gnats with GNATS_RELEASE_BASED defined.
$site_release_based = 0;

# Name you want in the page banner and banner color.
$site_banner_text = 'gnatsweb';
$site_banner_background = '#000000';
$site_banner_foreground = '#ffffff';

# Page background color -- not used unless defined.
#$site_background = '#c0c0c0';
#GCC-LOCAL begin.
$site_background = '#ffffff';
#GCC-LOCAL end.

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
#     For examples of some of the things you can do with the site_callback
#     subroutine, see gnatsweb-site-sente.pl.
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

# Use CGI::Carp first, so that fatal errors come to the browser, including
# those caused by old versions of CGI.pm.
use CGI::Carp qw/fatalsToBrowser/;
# 8/22/99 kenstir: CGI.pm-2.50's file upload is broken.
# 9/19/99 kenstir: CGI.pm-2.55's file upload is broken.
use CGI 2.56 qw/:standard :netscape/;
use Socket;
use IO::Handle;

# Version number + RCS revision number
$VERSION = '2.6';
$REVISION = (split(/ /, '$Revision: 1.135 $ '))[1];

# width of text fields
$textwidth = 60;

# where to get help -- a web site with translated info documentation
#$gnats_info_top = 'http://www.hyperreal.org/info/gnuinfo/index?(gnats)';
$gnats_info_top = 'http://sources.redhat.com/gnats/';
#GCC-LOCAL begin.
$gnats_info_top = '/gnats.html';
#GCC-LOCAL begin.

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
  print "<tt>server_reply: $_</tt><br>\n" if defined($reply_debug);
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
    print "<tt>read_server: $_</tt><br>\n" if defined($reply_debug);
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
  my $debug = 0;
  print SOCK "$cmd\n";
  warn "client_cmd: $cmd" if $debug;
  print "<tt>client_cmd: <pre>$cmd</pre></tt><br>\n"
        if defined($client_cmd_debug);
  return get_reply();
}

# Return true if module MIME::Base64 is available.  If available, it's
# loaded the first time this sub is called.
sub can_do_mime
{
  return $can_do_mime if (defined($can_do_mime));

  eval 'use MIME::Base64;';
  if ($@) {
    warn "NOTE: Can't use file upload feature without MIME::Base64 module\n";
    $can_do_mime = 0;
  }
  else {
    $can_do_mime = 1;
  }
  $can_do_mime;
}

# Take the file attachment's file name, and return only the tail.  Don't
# want to store any path information, for security and clarity.  Support
# both DOS-style and Unix-style paths here, because we have both types of
# clients.
sub attachment_filename_tail
{
  my($filename) = @_;
  $filename =~ s,.*/,,;  # Remove leading Unix path elements.
  $filename =~ s,.*\\,,; # Remove leading DOS path elements.

  return $filename;
}

# Retrieve uploaded file attachment.  Return it as
# ($filename, $content_type, $data).  Returns (undef,undef,undef)
# if not present.
#
# See 'perldoc CGI' for details about this code.
sub get_attachment
{
  my $upload_param_name = shift;
  my $debug = 0;
  my $filename = $q->param($upload_param_name);
  return (undef, undef, undef) unless $filename;

  # 9/6/99 kenstir: My testing reveals that if uploadInfo returns undef,
  # then you can't read the file either.
  warn "get_attachment: filename=$filename\n" if $debug;
  my $hashref = $q->uploadInfo($filename);
  if (!defined($hashref)) {
    die "Got attachment filename ($filename) but no attachment data!  Probably this is a programming error -- the form which submitted this data must be multipart/form-data (start_multipart_form()).";
  }
  if ($debug) {
    while (($k, $v) = each %$hashref) {
      warn "get_attachment: uploadInfo($k)=$v\n";
    }
  }

  # 9/6/99 kenstir: When testing locally on Linux, a .gz file yielded
  # no Content-Type.  Therefore, have to assume binary.  Would like to
  # check (-B $fh) to see if the stream is binary but that doesn't work.
  my $ctype = $hashref->{'Content-Type'} || 'application/octet-stream';
  warn "get_attachment: Content-Type=$ctype\n" if $debug;

  my $data = '';
  my $buf;
  my $fh = $q->upload($upload_param_name);
  warn "get_attachment: fh=$fh\n" if $debug;
  while (read($fh, $buf, 1024)) {
    $data .= $buf;
  }
  close $fh;

  return ($filename, $ctype, $data);
}

# Retrieve uploaded file attachment, and encode it so that it's 
# printable, for inclusion into the PR text.
#
# Returns the printable text representing the attachment.  Returns '' if
# the attachment was not present.
sub encode_attachment
{
  my $upload_param_name = shift;
  my $debug = 0;

  return '' unless can_do_mime();

  my ($filename, $ctype, $data) = get_attachment($upload_param_name);
  return '' unless $filename;

  # Strip off path elements in $filename.
  $filename = attachment_filename_tail($filename);

  warn "encode_attachment: $filename was ", length($data), " bytes of $ctype\n"
        if $debug;
  my $att = '';

  # Plain text is included inline; all else is encoded.
  $att .= "Content-Type: $ctype; name=\"$filename\"\n";
  if ($ctype eq 'text/plain') {
    $att .= "Content-Disposition: inline; filename=\"$filename\"\n\n";
    $att .= $data;
  }
  else {
    $att .= "Content-Transfer-Encoding: base64\n";
    $att .= "Content-Disposition: attachment; filename=\"$filename\"\n\n";
    $att .= encode_base64($data);
  }
  warn "encode_attachment: done\n" if $debug;

  return $att;
}

# Takes the encoded file attachment, decodes it and returns it as a hashref.
sub decode_attachment
{
  my $att = shift;
  my $debug = 0;
  my $hash_ref = {'original_attachment' => $att};

  # Split the envelope from the body.
  my ($envelope, $body) = split(/\n\n/, $att);
  return $hash_ref unless ($envelope && $body);

  # Got the idea from this from the perldoc for split.
  # The extra map step is the only way I could think of to strip
  # the trailing newlines from the hash values.
  warn "decode_attachment: envelope=>$envelope<=\n" if $debug;
  #%$hash_ref = (USELESS_LEADING_ENTRY => split /^(\S*?):\s*/m, $envelope);
  %$hash_ref = (map {chomp; $_;}
               (USELESS_LEADING_ENTRY => split /^(\S*?):\s*/m, $envelope));
  delete($$hash_ref{USELESS_LEADING_ENTRY});

  # Keep the original_attachment intact.
  $$hash_ref{'original_attachment'} = $att;

  if (!$$hash_ref{'Content-Type'}
      || !$$hash_ref{'Content-Disposition'})
  {
    die "Unable to parse file attachment";
  }

  # Parse filename.
  # Note: the extra \ before the " is just so that perl-mode can parse it.
  if ($$hash_ref{'Content-Disposition'} !~ /(\S+); filename=\"([^\"]+)\"/) {
    die "Unable to parse file attachment Content-Disposition";
  }
  $$hash_ref{'filename'} = attachment_filename_tail($2);

  # Decode the data if encoded.
  if (exists($$hash_ref{'Content-Transfer-Encoding'})
      && $$hash_ref{'Content-Transfer-Encoding'} eq 'base64')
  {
    $$hash_ref{'data'} = decode_base64($body);
  }
  else {
    $$hash_ref{'data'} = $body;
  }

  return $hash_ref;
}

# Print file attachment browser and buttons to download the attachments.
# Which of these appear depend on the mode.
sub print_attachments
{
  my($fields_hash_ref, $mode) = @_;

  return unless can_do_mime();

  print "<tr><td valign=top><b>File Attachments:</b><td>";

  # Add file upload button for adding new attachment.
  if ($mode eq 'sendpr' || $mode eq 'edit') {
    print "Add a file attachment:<br>",
          $q->filefield(-name=>'attached_file',
                        -size=>50);
  }

  # Print table of existing attachments.
  # Add column with delete button in edit mode.
  my $array_ref = $$fields_hash_ref{'attachments'};
  my $table_rows_aref = [];
  my $i = 0;
  foreach $hash_ref (@$array_ref) {
    my $size = int(length($$hash_ref{'data'}) / 1024.0);
    $size = 1 if ($size < 1);
    my $row_data = $q->td( [ $q->submit('cmd', "download attachment $i"),
                             $$hash_ref{'filename'},
                             "${size}k" ] );
    $row_data .= $q->td($q->checkbox(-name=>'delete attachments',
                                     -value=>$i,
                                     -label=>"delete attachment $i"))
          if ($mode eq 'edit');
    push(@$table_rows_aref, $row_data);
    $i++;
  }
  if (@$table_rows_aref)
  {
    my $header_row_data = $q->th( ['download','filename','size' ] );
    $header_row_data .= $q->th('delete')
          if ($mode eq 'edit');
    print $q->table({-border=>1},
                    $q->Tr($header_row_data),
                    $q->Tr($table_rows_aref));
  }
}

# The user has requested download of a particular attachment.
# Serve it up.
sub download_attachment
{
  my $attachment_number = shift;
  my($pr) = $q->param('pr');
  die "download_attachment called with no PR number"
        if(!$pr);

  my(%fields) = readpr($pr);
  my $array_ref = $fields{'attachments'};
  my $hash_ref = $$array_ref[$attachment_number];
  print $q->header(-type => 'application/octet-stream',
                   -content_disposition => "attachment; filename=\"$$hash_ref{'filename'}\""),
        $$hash_ref{'data'};
}

# Add the given (gnatsweb-encoded) attachment to the %fields hash.
sub add_encoded_attachment_to_pr
{
  my($fields_hash_ref, $encoded_attachment) = @_;
  return unless $encoded_attachment;
  my $ary_ref = $$fields_hash_ref{'attachments'} || [];
  my $hash_ref = { 'original_attachment' => $encoded_attachment };
  push(@$ary_ref, $hash_ref);
  $$fields_hash_ref{'attachments'} = $ary_ref;
}

# Add the given (gnatsweb-decoded) attachment to the %fields hash.
sub add_decoded_attachment_to_pr
{
  my($fields_hash_ref, $decoded_attachment_hash_ref) = @_;
  return unless $decoded_attachment_hash_ref;
  my $ary_ref = $$fields_hash_ref{'attachments'} || [];
  push(@$ary_ref, $decoded_attachment_hash_ref);
  $$fields_hash_ref{'attachments'} = $ary_ref;
}

# Remove the given attachments from the %fields hash.
sub remove_attachments_from_pr
{
  my($fields_hash_ref, @attachment_numbers) = @_;
  return unless @attachment_numbers;
  my $ary_ref = $$fields_hash_ref{'attachments'} || [];
  foreach my $attachment_number (@attachment_numbers)
  {
    # Remove the attachment be replacing it with the empty hash.
    # The sub unparsepr skips these.
    $$ary_ref[$attachment_number] = {};
  }
}

# sendpr -
#     The Create PR page.
#
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

  print $q->start_multipart_form(),
        hidden_db(),
	$q->submit('cmd', 'submit'),
	" or ",
	$q->reset(-name=>'reset'),
	"<hr>\n",
	"<table>";
  my $def_email = $global_prefs{'email'}
        || cb('get_default_value', 'email') || '';
  print "<tr><td><b>Reporter's email:</b><td>",
        $q->textfield(-name=>'email',
                      -default=>$def_email,
                      -size=>$textwidth),
	"<tr><td><b>CC these people<br>on PR status email:</b><td>",
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
    $default = 'serious'                   if /Severity/;
    $default = 'medium'                    if /Priority/;
    $default = $global_prefs{'Submitter-Id'} || 'unknown' if /Submitter-Id/;
    $default = $global_prefs{'Originator'} if /Originator/;
    $default = grep(/^unknown$/i, @category) ? "unknown" : $category[0]
                                           if /Category/;
    $default = $config{'DEFAULT_RELEASE'} if /Release/;
    $default = cb("sendpr_$lc_fieldname") || $default;

    # The "intro" provides a way for the site callback to print something
    # at the top of a given field.
    my $intro = cb("sendpr_intro_$lc_fieldname") || '';

    if ($fieldnames{$_} & $ENUM)
    {
      print "<tr><td><b>$_:</b><td>",
            $intro,
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
            $intro,
            $q->textarea(-name=>$_,
                         -cols=>$textwidth,
                         -rows=>$rows,
                         -default=>$default);
      # Create file upload button after Description.
      print_attachments(\%fields, 'sendpr') if /Description/;
    }
    else
    {
      print "<tr><td><b>$_:</b><td>",
            $intro,
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
  my $email_addr = '[^@\s]+(@\S+\.\S+)?';
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
#  $err = validate_email_field('CC', $fields{'cc'});
#  push(@errors, $err) if $err;
  $err = validate_email_field('X-GNATS-Notify', $fields{'X-GNATS-Notify'});
  push(@errors, $err) if $err;

  # validate some other fields
  push(@errors, "Category is blank or 'unknown'")
        if($fields{'Category'} =~ /^\s*$/ || $fields{'Category'} eq "unknown");
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

  # Handle the attached_file, if any.
  add_encoded_attachment_to_pr(\%fields, encode_attachment('attached_file'));

  # Compose the message
  my $text = unparsepr('send', %fields);
  $text = <<EOT . $text;
To: $config{'GNATS_ADDR'}
CC: $fields{'X-GNATS-Notify'}
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
          $q->pre($q->escapeHTML($text)),
          "<hr>";
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

sub get_viewpr_url
{
  my $pr = shift;
  $q->url() . "?cmd=view&pr=$pr&database=$global_prefs{'database'}";
}

# Return a link which sends email regarding the current PR.
sub get_mailto_link
{
  my($pr,%fields) = @_;
  my $mailto  = $q->escape(scalar(interested_parties($pr, %fields)));
  my $subject = $q->escape("Re: $fields{'Category'}/$pr");
  my $body    = $q->escape(get_viewpr_url($pr));

  # MSIE users fork Outlook and Outlook Express,
  # they need semicolons and the &'s used to view-pr need more quoting
  if ($ENV{'HTTP_USER_AGENT'} =~ /MSIE/)
  {
    my $ecomma     = $q->escape(",");
    my $esemicolon = $q->escape(";");
    my $ampsand    = $q->escape("&");
    $mailto =~ s/$ecomma/$esemicolon/g ;
    $body =~ s/$ampsand/%2526/g ;
  }

  return "<a href=\"mailto:$mailto?Subject=$subject&Body=$body\">"
        . "send email to interested parties</a>\n";
}

# Look for text that looks like URLs and turn it into actual links.
sub mark_urls
{
  my ($val) = @_;
  # This probably doesn't catch all URLs, but one hopes it catches the
  # majority.
  $val =~ s/\b((s?https?|ftp):\/\/[-a-zA-Z0-9_.]+(:[0-9]+)?[-a-zA-Z0-9_\$.+\!*\(\),;:\@\&=?~\#\/]*)/\<a href="$1">$1\<\/a\>/g;
  return $val;
}

sub view
{
  my($viewaudit, $tmp) = @_;

  # For gcc.gnu.org, force audit trail to always be shown.
  $viewaudit = 1;

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
        hidden_db(),
	$q->hidden('pr', $pr);

  # print 'edit' and 'view audit-trail' buttons as appropriate, mailto link
  print $q->submit('cmd', 'edit')             if (can_edit());
  print " or "                                if (can_edit() && !$viewaudit);
  print $q->submit('cmd', 'view audit-trail') if (!$viewaudit);
  print " or ",
        get_mailto_link($pr, %fields);

  print $q->hr(),
        "<table>";
  print "<tr><td><b>Reporter's email:</b><td>",
        $q->tt($fields{'Reply-To'}),
#	"<tr><td><b>Others to notify<br>of updates to this PR:</b><td>",
	"<tr><td><b>CC these people<br>on PR status email:</b><td>",
	$q->tt($fields{'X-GNATS-Notify'}),
        # a blank row, to separate header info from PR info
        "<tr><td>&nbsp;<td>&nbsp;\n";

  foreach (@fieldnames)
  {
    next if $_ eq 'Audit-Trail';
    my $val = $q->escapeHTML($fields{$_}) || ''; # to avoid -w warning
    my $valign = '';
    if ($fieldnames{$_} & $MULTILINE)
    {
      $valign = 'valign=top';
      $val =~ s/$/<br>/gm;
      $val =~ s/<br>$//; # previous substitution added one too many <br>'s
      $val = mark_urls($val);
    }
    print "<tr><td nowrap $valign><b>$_:</b><td>",
          $q->tt($val), "\n";
    # Print attachments after Description.
    print_attachments(\%fields, 'view') if /Description/;
  }
  print "</table>",
        $q->hr();

  # print 'edit' and 'view audit-trail' buttons as appropriate, mailto link
  print $q->submit('cmd', 'edit')             if (can_edit());
  print " or "                                if (can_edit() && !$viewaudit);
  print $q->submit('cmd', 'view audit-trail') if (!$viewaudit);
  print " or ",
        get_mailto_link($pr, %fields);

  print $q->end_form();

  # Footer comes before the audit-trail.
  page_footer($page);

  if($viewaudit)
  {
    print "<h3>Audit Trail:</h3>\n",
          mark_urls($q->pre($q->escapeHTML($fields{'Audit-Trail'})));
  }

  page_end_html($page);
}

# edit -
#     The Edit PR page.
#
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

  print $q->start_multipart_form(),
        hidden_db(),
        $q->submit('cmd', 'submit edit'),
        " or ",
        $q->reset(-name=>'reset'),
        " or ",
        get_mailto_link($pr, %fields),
	$q->hidden(-name=>'Editor',
                   -value=>$db_prefs{'user'},
                   -override=>1),
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
#	"<tr><td><b>Others to notify<br>of updates to this PR:</b><td>",
	"<tr><td><b>CC these people<br>on PR status email:</b><td>",
	$q->textfield(-name=>'X-GNATS-Notify',
                      -default=>$fields{'X-GNATS-Notify'},
		      -size=>$textwidth),
        # a blank row, to separate header info from PR info
        "<tr><td>&nbsp;<td>&nbsp;\n";

  foreach (@fieldnames)
  {
    next if ($fieldnames{$_} && ($fieldnames{$_} & $EDITEXCLUDE));
    my $lc_fieldname = field2param($_);

    # The "intro" provides a way for the site callback to print something
    # at the top of a given field.
    my $intro = cb("edit_intro_$lc_fieldname") || '';

    if ($fieldnames{$_} && ($fieldnames{$_} & $ENUM))
    {
      print "<tr><td><b>$_:</b><td>",
            $intro,
            $q->popup_menu(-name=>$_,
                           -values=>\@$lc_fieldname,
                           -default=>$fields{$_});
    }
    elsif ($fieldnames{$_} && ($fieldnames{$_} & $MULTILINE))
    {
      my $rows = 4;
      $rows = 8 if /Description/;
      $rows = 2 if /Environment/;
      print "<tr><td valign=top><b>$_:</b><td>",
            $intro,
            $q->textarea(-name=>$_,
                         -cols=>$textwidth,
                         -rows=>$rows,
                         -default=>$fields{$_});
      # Print attachments after Description.
      print_attachments(\%fields, 'edit') if /Description/;
    }
    else
    {
      print "<tr><td><b>$_:</b><td>",
            $intro,
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
        " or ",
        get_mailto_link($pr, %fields),
	$q->end_form(),
	$q->hr();

  # Footer comes before the audit-trail.
  page_footer($page);

  print "<h3>Audit-Trail:</h3>\n",
        mark_urls($q->pre($q->escapeHTML($fields{'Audit-Trail'})));
  page_end_html($page);
}

# Print out the %fields hash for debugging.
sub debug_print_fields
{
  my $fields_hash_ref = shift;
  foreach my $f (sort keys %$fields_hash_ref)
  {
    print "<tr valign=top><td>$f</td><td>",
          $q->pre($q->escapeHTML($$fields_hash_ref{$f})),
          "</td></tr>\n";
  }
  my $aref = $$fields_hash_ref{'attachments'} || [];
  my $i=0;
  foreach my $href (@$aref) {
    print "<tr valign=top><td>attachment $i<td>",
          ($$href{'original_attachment'}
           ?  $$href{'original_attachment'} : "--- empty ---");
    $i++;
  }
  print "</table></font><hr>\n";
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

  # Retrieve new attachment (if any) before locking PR, in case it fails.
  my $encoded_attachment = encode_attachment('attached_file');

  my(%oldfields) = lockpr($pr, $db_prefs{'user'});
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

    # Add the attached file, if any, to the new PR.
    add_encoded_attachment_to_pr(\%fields, $encoded_attachment);

    # Delete any attachments, if directed.
    my(@deleted_attachments) = $q->param('delete attachments');
    remove_attachments_from_pr(\%fields, @deleted_attachments);

    if ($debug)
    {
      print "<h3>debugging -- PR edits not submitted</h3><font size=1><table>";
      debug_print_fields(\%fields);
      last LOCKED;
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

    if($db_prefs{'user'} eq "" || $fields{'Responsible'} eq "")
    {
      page_heading($page, 'Error');
      print "<h3>Responsible party is '$fields{'Responsible'}', user is '$db_prefs{'user'}'!</h3>\n";
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
	  $audittrail .= "$_-Changed-By: $db_prefs{'user'}\n";
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
      #print $q->pre($q->escapeHTML("mailto->$mailto<-\n"));
      #last LOCKED; # debug
      if($mailto ne "" && $audittrail ne "")
      {
        # Use email address in responsible file as From, if present.
        my $from = $responsible_address{$db_prefs{'user'}}
              || $db_prefs{'user'};
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
        hidden_db(),
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
  my(@columns) = split(' ', $global_prefs{'columns'});
  @columns = @deffields unless @columns;
  print $q->scrolling_list(-name=>'columns',
                           -values=>\@fields,
                           -defaults=>\@columns,
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
  print $q->start_form(),
        hidden_db();

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

  my(@columns) = split(' ', $global_prefs{'columns'});
  @columns = @deffields unless @columns;
  print "<table border=1 bgcolor=$cell_bg>",
        "<caption>Select Columns to Display</caption>",
        "<tr valign=top><td>Display these columns:<td>",
        $q->scrolling_list(-name=>'columns',
                           -values=>\@fields,
                           -defaults=>\@columns,
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
  client_cmd("orig $db_prefs{'user'}") if($originatedbyme);
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
    $val = $b->[0] <=> $a->[0];
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
  my $myurl = $q->url();
  foreach (@sorted_prs)
  {
    print "<tr valign=top>";

    my($id, $cat, $syn, $conf, $sev,
       $pri, $resp, $state, $class, $sub,
       $arrival, $orig, $release, $lastmoddate, $closeddate,
       $quarter, $keywords, $daterequired) = @{$_};
    print "<td nowrap><a href=\"$sn?cmd=view&pr=$id&database=$global_prefs{'database'}\">$id</a>"; 
    print " <a href=\"$sn?cmd=edit&pr=$id&database=$global_prefs{'database'}\"><font size=-1>edit</font></a>"
          if can_edit();
    print "<td nowrap>$cat"                      if $fields{'category'};
    print "<td nowrap>$conf"                     if $fields{'confidential'};
    print "<td nowrap>$state[$state]"            if $fields{'state'};
    print "<td nowrap>$class[$class]"            if $fields{'class'};
    print "<td nowrap>$severity[$sev]"           if $fields{'severity'};
    print "<td nowrap>$priority[$pri]"           if $fields{'priority'};
    print "<td nowrap>", nonempty($release)      if $fields{'release'};
    print "<td nowrap>", nonempty($quarter)       if($site_release_based
                                                    && $fields{'quarter'});
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
                              -path => $global_cookie_path,
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
  print "<p>Your query \"$queryname\" has been saved.  It will be available ",
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
    print "<table cellspacing=0 cellpadding=0 border=0>",
          "<tr valign=top>",
          $q->start_form(),
          "<td>",
          hidden_db(),
          $q->submit('cmd', 'submit stored query'),
          "<td>&nbsp;<td>",
          $q->popup_menu(-name=>'queryname',
                         -values=>[ sort(keys %stored_queries) ]),
          $q->end_form(),
          $q->start_form(),
          "<td>",
          $q->hidden('return_url', $q->self_url()),
          hidden_db(),
          $q->submit('cmd', 'delete stored query'),
          "<td>&nbsp;<td>",
          $q->popup_menu(-name=>'queryname',
                         -values=>[ sort(keys %stored_queries) ]),
          $q->end_form(),
          "</tr></table>";
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
    # 9/10/99 kenstir: Must use full (not relative) URL in redirect.
    # Patch by Elgin Lee <ehl@terisa.com>.
    my $query_url = $q->url() . '?cmd=' . $q->escape('submit query')
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

# delete_stored_query -
#     Delete the query named in the param 'queryname'.
#
#     Queries are stored as individual cookies named
#     'gnatsweb-query-$queryname'.
#
sub delete_stored_query
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
    # The negative -expire causes the old cookie to expire immediately.
    my $expire_cookie_with_path =
          $q->cookie(-name => "gnatsweb-query-$queryname",
                     -value => 'does not matter',
                     -path => $global_cookie_path,
                     -expires => '-1d');
    my $expire_cookies = $expire_cookie_with_path;

    # If we're using a non-empty $global_cookie_path, then we need to
    # create two expire cookies.  One or the other will delete the stored
    # query, depending on whether the query was created with this version
    # of gnatsweb, or with an older version.
    if ($global_cookie_path)
    {
      my $expire_cookie_no_path =
            $q->cookie(-name => "gnatsweb-query-$queryname",
                       -value => 'does not matter',
                       # No -path here!
                       -expires => '-1d');
      $expire_cookies = [ $expire_cookie_with_path, $expire_cookie_no_path ];
    }

    # Return the user to the page they were viewing when they pressed
    # 'delete stored query'.
    print $q->redirect(-cookie => $expire_cookies,
                       -location => $q->param('return_url'));
  }
}

sub help_page
{
  my $page = 'Help';
  page_start_html($page);
  page_heading($page, 'Help', 1);

  #GCC-LOCAL begin.
  #print p('Welcome to our problem report database.');
  print p('Welcome to the GCC problem report database.');
  #GCC-LOCAL end.
  print p('This web interface is called gnatsweb, ',
          'the database system itself is called gnats.');
  print p('For details, please ',
          a({-href=>"$gnats_info_top"}, 'refer to our documentation.'));

  page_footer($page);
  page_end_html($page);
}

# hidden_db -
#    Return hidden form element to maintain current database.  This
#    enables people to keep two browser windows open to two databases.
#
sub hidden_db
{
  return $q->hidden(-name=>'database', -value=>$global_prefs{'database'}, -override=>1);
}

# one_line_form -
#     One line, two column form used for main page.
#
sub one_line_form
{
  my($label, @form_body) = @_;
  my $valign = 'baseline';
  return $q->Tr({-valign=>$valign},
                $q->td($q->b($label)),
                $q->td($q->start_form(), hidden_db(), @form_body,
                       $q->end_form()));
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

  my $top_buttons_html = cb('main_page_top_buttons') || '';
  print $top_buttons_html;

  print one_line_form('Create Problem Report:',
                      submit('cmd', 'create'));
  # Only include Edit action if user is allowed to edit PRs.
  # Note: include hidden 'cmd' so user can simply type into the textfield
  # and press Enter w/o clicking.
  print one_line_form('Edit Problem Report:',
                      hidden(-name=>'cmd', -value=>'edit', -override=>1),
                      submit('cmd', 'edit'),
                      '#',
                      textfield(-size=>6, -name=>'pr'))
        if can_edit();
  print one_line_form('View Problem Report:',
                      hidden(-name=>'cmd', -value=>'view', -override=>1),
                      submit('cmd', 'view'),
                      '#',
                      textfield(-size=>6, -name=>'pr'));
  print one_line_form('Query Problem Reports:',
                      submit('cmd', 'query'));
  print one_line_form('Advanced Query:',
                      submit('cmd', 'advanced query'));
  print one_line_form('Login Again:',
                      submit('cmd', 'login again'));
  print one_line_form('Get Help:',
                      submit('cmd', 'help'));

  my $bot_buttons_html = cb('main_page_bottom_buttons') || '';
  print $bot_buttons_html;

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

  # Call start_html, with -bgcolor if we need to override that.
  my @args = (-title=>"$title - $site_banner_text");
  push(@args, -bgcolor=>$site_background)
        if defined($site_background);
  print $q->start_html(@args);

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
      color:       $site_banner_foreground;
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
      color:       $site_banner_foreground;
      font-family: 'Courier New', monospace;
      font-size:   28pt;
      font-weight: 600;
      text-decoration: none;
END_OF_STYLE
  }
  my($row, $banner);
  my $url = "$sn";
  $url .= "?database=$global_prefs{'database'}"
        if defined($global_prefs{'database'});
  $row = $q->Tr($q->td({-align=>'right'},
                       $q->a({-style=>$style, -href=>$url},
                             ' ', $site_banner_text, ' ')));
  $banner = $q->table({-bgcolor=>$site_banner_background, -width=>'100%',
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

  if ($db_prefs{'user'} && defined($display_user_info))
  {
    $rightcol= "<tt><small>User: $db_prefs{'user'}<br>" .
               "Database: $global_prefs{'database'}<br>" .
               "Access: $access_level</small></tt>";
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

# initialize -
#     Initialize gnatsd-related globals and login to gnatsd.
#
sub initialize
{
  my $regression_testing = shift;

  @severity = ("all", "critical", "serious", "non-critical");
  @priority = ("all", "high", "medium", "low");
  @confidential = ("all", "no");

  # @fields - param names of columns displayable in query results
  # @deffields - default displayed columns
  @deffields = ("category", "state", "responsible", "synopsis");
  #GCC-LOCAL begin.
  @deffields = ("category", "state", "class", "responsible", "synopsis");
  #GCC-LOCAL end.
  @fields = ("category", "confidential", "state", "class",
             "severity", "priority",
             "release", "quarter", "responsible", "submitter_id", "originator",
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
    "Quarter",
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
    "Quarter"        => 0,
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

  $attachment_delimiter = "----gnatsweb-attachment----\n";

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
    "quarter"	      => 'qrtr',
    "keywords"	      => 'kywd',
    "requiredbefore"  => 'bfor',
    "requiredafter"   => 'aftr',
  );

  # clear out some unused fields if not used
  if (!$site_release_based)
  {
    @fields = grep(!/quarter|keywords|date_required/, @fields);
    @fieldnames = grep(!/Quarter|Keywords|Date-Required/, @fieldnames);
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
  # an error in the user or database cookie values can cause a user to
  # get in a bad state.
  LOGIN:
  {
    local($suppress_client_exit) = 1
          unless $regression_testing;

    # Issue CHDB command; revert to login page if it fails.
    ($response) = client_cmd("chdb $global_prefs{'database'}");
    if (!$response)
    {
      login_page($q->self_url());
      exit();
    }

    # Get user permission level from USER command.  Revert to the
    # login page if the command fails.
    ($response) = client_cmd("user $db_prefs{'user'} $db_prefs{'password'}");
    if (!$response)
    {
      login_page($q->self_url());
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
sub trim_responsible
{
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
  # 9/18/99 kenstir: This two-liner can almost replace the next 30 or so
  # lines of code, but not quite.  It strips leading spaces from multiline
  # fields.
  #my $prtext = join("\n", @_);
  #my(%fields) = ('envelope' => split /^>(\S*?):\s*/m, $prtext);
  #  my $prtext = join("\n", @_);
  #  my(%fields) = ('envelope' => split /^>(\S*?):(?: *|\n)/m, $prtext);

  my $debug = 0;

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
    # 8/25/99 ehl: Grab these fields only out of the envelope, not
    # any other multiline field.
    if($hdrmulti eq "envelope" &&
       ($hdr eq "Reply-To" || $hdr eq "From" || $hdr eq "X-GNATS-Notify"))
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

  # Ensure that the pseudo-fields are initialized to avoid perl warnings.
  $fields{'X-GNATS-Notify'} ||= '';

  # 3/30/99 kenstir: For some reason Unformatted always ends up with an
  # extra newline here.
  $fields{'Unformatted'} =~ s/\n$//;

  # Decode attachments stored in Unformatted field.
  my $any_attachments = 0;
  if (can_do_mime()) {
    my(@attachments) = split(/$attachment_delimiter/, $fields{'Unformatted'});
    # First element is any random text which precedes delimited attachments.
    $fields{'Unformatted'} = shift(@attachments);
    foreach $attachment (@attachments) {
      warn "att=>$attachment<=\n" if $debug;
      $any_attachments = 1;
      add_decoded_attachment_to_pr(\%fields, decode_attachment($attachment));
    }
  }

  if ($debug) {
    warn "--- parsepr fields ----\n";
    my %fields_copy = %fields;
    foreach (@fieldnames)
    {
      warn "$_ =>$fields_copy{$_}<=\n";
      delete $fields_copy{$_}
    }
    warn "--- parsepr pseudo-fields ----\n";
    foreach (sort keys %fields_copy) {
      warn "$_ =>$fields_copy{$_}<=\n";
    }
    warn "--- parsepr attachments ---\n";
    my $aref = $fields{'attachments'} || [];
    foreach $href (@$aref) {
      warn "    ----\n";
      while (($k,$v) = each %$href) {
        warn "    $k =>$v<=\n";
      }
    }
  }

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
  my $debug = 0;

  # First create or reconstruct the Unformatted field containing the
  # attachments, if any.
  $fields{'Unformatted'} ||= ''; # Default to empty.
  warn "unparsepr 1 =>$fields{'Unformatted'}<=\n" if $debug;
  my $array_ref = $fields{'attachments'};
  foreach $hash_ref (@$array_ref) {
    my $attachment_data = $$hash_ref{'original_attachment'};
    # Deleted attachments leave empty hashes behind.
    next unless defined($attachment_data);
    $fields{'Unformatted'} .= $attachment_delimiter . $attachment_data;
  }
  warn "unparsepr 2 =>$fields{'Unformatted'}<=\n" if $debug;

  # Reconstruct the text of the PR into $text.
  $text = $fields{'envelope'};
  foreach (@fieldnames)
  {
    # Do include Unformatted field in 'send' operation, even though
    # it's excluded.  We need it to hold the file attachment.
    #next if($purpose eq "send" && $fieldnames{$_} & $SENDEXCLUDE);
    next if(($purpose eq 'send')
            && ($fieldnames{$_} & $SENDEXCLUDE)
            && ($_ ne 'Unformatted'));
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
  my $list;

  ## Get list from MLPR command.
  #@people = client_cmd("mlpr $pr");
  # Ignore intro message
  #@people = grep(!/Addresses to notify/, @people);

  # Get list of people by constructing it ourselves.
  @people = ();
  foreach $list ($fields{'Reply-To'},
                 $fields{'Responsible'},
                 $fields{'X-GNATS-Notify'},
#GCC-LOCAL begin.
#                 $category_notify{$fields{'Category'}},
#                 $submitter_contact{$fields{'Submitter-Id'}},
#                 $submitter_notify{$fields{'Submitter-Id'}},
#GCC-LOCAL end.
                 $config{'GNATS_ADDR'})
  {
    if (defined($list)) {
      foreach $person (split(/,/, $list)) {
        push(@people, $person) if $person;
      }
    }
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

# login_page_javascript -
#     Returns some Javascript code to test if cookies are being accepted.
#
sub login_page_javascript
{
  my $ret = q{
<SCRIPT LANGUAGE="JavaScript1.2" TYPE="text/javascript">
//<!-- 
// JavaScript courtesy of webcoder.com.

function getCookie(name) {
    var cname = name + "=";               
    var dc = document.cookie;             
    if (dc.length > 0) {              
        begin = dc.indexOf(cname);       
        if (begin != -1) {           
            begin += cname.length;       
            end = dc.indexOf(";", begin);
            if (end == -1) end = dc.length;
            return unescape(dc.substring(begin, end));
        } 
    }
    return null;
}

function setCookie(name, value, expires) {
    document.cookie = name + "=" + escape(value) + "; path=/" +
        ((expires == null) ? "" : "; expires=" + expires.toGMTString());
}

function delCookie(name) {
    document.cookie = name + "=; path=/; expires=Thu, 01-Jan-70 00:00:01 GMT";
}

exp = new Date();
exp.setTime(exp.getTime() + (1000 * 60 * 60)); // +1 hour
setCookie("gnatsweb-test-cookie", "whatever", exp);
val = getCookie("gnatsweb-test-cookie");
delCookie("gnatsweb-test-cookie");
if (val == null) {
    document.write("<h2>Warning: your browser is not accepting cookies</h2>"
        + "Gnatsweb requires cookies to keep track of your login and other "
        + "information.  Please enable cookies before logging in.");
}

//-->
</SCRIPT>
  };
}

# login_page -
#     Show the login page.
#
#     If $return_url passed in, then we are showing the login page because
#     the user failed to login.  In that case, when the login is
#     successful, we want to redirect to the given url.  For example, if a
#     user follows a ?cmd=view url, but hasn't logged in yet, then we want
#     to forward him to the originally requested url after logging in.
#
sub login_page
{
  my $return_url = shift;
  my $page = 'Login';
  page_start_html($page);
  page_heading($page, 'Login');

  print login_page_javascript();

  client_init();
  my(@dbs) = client_cmd("dbla");
  #GCC-LOCAL begin: Do not offer all database, just "gcc". 
  @dbs = ("gcc");
  #GCC-LOCAL end.
  my $def_user = $db_prefs{'user'} || $ENV{'REMOTE_USER'};
  # Lousy assumption alert!  Assume that if the site is requiring browser
  # authentication (REMOTE_USER is defined), then their gnats passwords
  # are not really needed; use the username as the default.
  my $def_password = $db_prefs{'password'} || $ENV{'REMOTE_USER'};
  print $q->start_form(),
        "<p>Use username '<b>guest</b>' and password '<b>guest</b>' for".
        " read-only and bug reporting access.",
        " Unfortunately, GNATSweb requires cookies to keep track".
        " of your login and other information.  Please enable cookies".
        " before logging in.",
        "<table>",
        "<tr><td>User Name:<td>",
        $q->textfield(-name=>'user',
                      -size=>20,
		      -default=>$def_user),
        "<tr><td>Password:<td>",
        $q->password_field(-name=>'password',
                           -value=>$def_password,
                           -size=>20),
	"<tr><td>Database:<td>",
	$q->popup_menu(-name=>'database',
	               -values=>\@dbs,
                       -default=>$global_prefs{'database'}),
        "</table>";
  if (defined($return_url))
  {
    print $q->hidden('return_url', $return_url);
  }
  print $q->submit('cmd','login'),
        $q->end_form();
  page_footer($page);
  page_end_html($page);
}

sub debug_print_all_cookies
{
  # Debug: print all our cookies into server log.
  warn "================= all cookies ===================================\n";
  my @c;
  $i = 0;
  foreach my $y ($q->cookie())
  {
    @c = $q->cookie($y);
    warn "got cookie: length=", scalar(@c), ": $y =>@c<=\n";
    $i += length($y);
  }
#  @c = $q->raw_cookie();
#  warn "debug 0.5: @c:\n";
#  warn "debug 0.5: total size of raw cookies: ", length("@c"), "\n";
}

# set_pref -
#     Set the named preference.  Param values override cookie values, and
#     don't set it if we end up with an undefined value.
#
sub set_pref
{
  my($pref_name, $pref_hashref, $cval_hashref) = @_;
  my $val = $q->param($pref_name) || $$cval_hashref{$pref_name};
  $$pref_hashref{$pref_name} = $val
        if defined($val);
}

# init_prefs -
#     Initialize global_prefs and db_prefs from cookies and params.
#
sub init_prefs
{
  my $debug = 0;

  if ($debug) {
    debug_print_all_cookies();
    use Data::Dumper;
    $Data::Dumper::Terse = 1;
    warn "-------------- init_prefs -------------------\n";
  }

  # Global prefs.
  my %cvals = $q->cookie('gnatsweb-global');
  if (! %cvals) {
    $global_no_cookies = 1;
  }
  %global_prefs = ();
  set_pref('database', \%global_prefs, \%cvals);
  set_pref('email', \%global_prefs, \%cvals);
  set_pref('Originator', \%global_prefs, \%cvals);
  set_pref('Submitter-Id', \%global_prefs, \%cvals);

  # columns is treated differently because it's an array which is stored
  # in the cookie as a joined string.
  if ($q->param('columns')) {
    my(@columns) = $q->param('columns');
    $global_prefs{'columns'} = join(' ', @columns);
  }
  elsif (defined($cvals{'columns'})) {
    $global_prefs{'columns'} = $cvals{'columns'};
  }

  # DB prefs.
  my $database = $global_prefs{'database'} || '';
  %cvals = $q->cookie("gnatsweb-db-$database");
  %db_prefs = ();
  set_pref('user', \%db_prefs, \%cvals);
  set_pref('password', \%db_prefs, \%cvals);

  # Debug.
  warn "global_prefs = ", Dumper(\%global_prefs) if $debug;
  warn "db_prefs = ", Dumper(\%db_prefs) if $debug;
}

# create_global_cookie -
#     Create cookie from %global_prefs.
#
sub create_global_cookie
{
  my $debug = 0;
  # As of gnatsweb-2.6beta, the name of this cookie changed.  This was
  # done so that the old cookie would not be read.
  my $cookie = $q->cookie(-name => 'gnatsweb-global',
                          -value => \%global_prefs,
                          -path => $global_cookie_path,
                          -expires => $global_cookie_expires);
  warn "storing cookie: $cookie\n" if $debug;
  return $cookie;
}

#
# MAIN starts here:
#
sub main
{
  # Load gnatsweb-site.pl if present.  Die if there are errors;
  # otherwise the person who wrote gnatsweb-site.pl will never know it.
  do './gnatsweb-site.pl' if (-e './gnatsweb-site.pl');
  die $@ if $@;

  # Make sure nobody tries to swamp our server with a huge file attachment.
  # Has to happen before 'new CGI'.
  $CGI::POST_MAX = $site_post_max if defined($site_post_max);

  # Create the query object.  Check to see if there was an error, which
  # happens if the post exceeds POST_MAX.
  $q = new CGI;
  if ($q->cgi_error())
  {
    print $q->header(-status=>$q->cgi_error());
          $q->start_html('Error');
    page_heading('Initialization failed', 'Error');
    print $q->h3('Request not processed: ', $q->cgi_error());
    exit();
  }

  $sn = $q->script_name;
  my $cmd = $q->param('cmd') || ''; # avoid perl -w warning

  ### Cookie-related code must happen before we print the HTML header.

  # What to use as the -path argument in cookies.  Using '' (or omitting
  # -path) causes CGI.pm to pass the basename of the script.  With that
  # setup, moving the location of gnatsweb.pl causes it to see the old
  # cookies but not be able to delete them.
  $global_cookie_path = '/';
  $global_cookie_expires = '+30d';
  init_prefs();

  # Big old switch to handle commands.
  if($cmd eq 'store query')
  {
    store_query();
    exit();
  }
  elsif($cmd eq 'delete stored query')
  {
    delete_stored_query();
    exit();
  }
  elsif($cmd eq 'submit stored query')
  {
    submit_stored_query();
    exit();
  }
  elsif($cmd eq 'login')
  {
    # User came from login page; store user/password/database in cookies,
    # and proceed to the appropriate page.
    my $global_cookie = create_global_cookie();
    my $db = $global_prefs{'database'};
    my $db_cookie = $q->cookie(-name => "gnatsweb-db-$db",
                               -value => \%db_prefs,
                               -path => $global_cookie_path,
                               -expires => $global_cookie_expires);
    my $expire_old_cookie = $q->cookie(-name => 'gnatsweb',
                               -value => 'does not matter',
                               #-path was not used for gnatsweb 2.5 cookies
                               -expires => '-1d');
    my $url = $q->param('return_url');
    # 11/27/99 kenstir: Try zero-delay refresh all the time.
    $url = $q->url() if (!defined($url));
    # 11/14/99 kenstir: For some reason doing cookies + redirect didn't
    # work; got a 'page contained no data' error from NS 4.7.  This cookie
    # + redirect technique did work for me in a small test case.
    #print $q->redirect(-location => $url,
    #                   -cookie => [$global_cookie, $db_cookie]);
    # So, this is sort of a lame replacement; a zero-delay refresh.
    print $q->header(-Refresh => "0; URL=$url",
                     -cookie => [$global_cookie, $db_cookie, $expire_old_cookie]),
          $q->start_html();
    my $debug = 0;
    if ($debug) {
      print "<h3>debugging params</h3><font size=1><pre>";
      my($param,@val);
      foreach $param (sort $q->param()) {
        @val = $q->param($param);
        printf "%-12s %s\n", $param, $q->escapeHTML(join(' ', @val));
      }
      print "</pre></font><hr>\n";
    }
    # Add a link to the new URL. In case the refresh/redirect above did not
    # work, at least the user can select the link manually.
    print $q->h3("Hold on... Redirecting...<br>".
                 "In case it does not work automatically, please follow ".
                 "<a href=\"$url\">this link</a>."),  
    $q->end_html();
    exit();
  }
  elsif($cmd eq 'login again')
  {
    # User is specifically requesting to login again.
    print $q->header();
    login_page();
    exit();
  }
  elsif(!$global_prefs{'database'}
        || !$db_prefs{'user'} || !$db_prefs{'password'})
  {
    # We don't have username/password/database; give login page then
    # redirect to the url they really want (self_url).
    print $q->header();
    login_page($q->self_url());
    exit();
  }
  elsif($cmd eq 'submit')
  {
    # User is submitting a new PR.  Store cookie because email address may
    # have changed.  This facilitates entering bugs the next time.
    print $q->header(-cookie => create_global_cookie());
    initialize();
    submitnewpr();
    exit();
  }
  elsif($cmd eq 'submit query')
  {
    # User is querying.  Store cookie because column display list may
    # have changed.
    print $q->header(-cookie => create_global_cookie());
    initialize();
    submitquery();
    exit();
  }
  elsif($cmd =~ /download attachment (\d+)/)
  {
    # User is downloading an attachment.  Must initialize but not print header.
    initialize();
    download_attachment($1);
    exit();
  }
  elsif($cmd eq 'create')
  {
    print $q->header();
    initialize();
    sendpr();
  }
  elsif($cmd eq 'view')
  {
    print $q->header();
    initialize();
    view(0);
  }
  elsif($cmd eq 'view audit-trail')
  {
    print $q->header();
    initialize();
    view(1);
  }
  elsif($cmd eq 'edit')
  {
    print $q->header();
    initialize();
    edit();
  }
  elsif($cmd eq 'submit edit')
  {
    print $q->header();
    initialize();
    submitedit();
  }
  elsif($cmd eq 'query')
  {
    print $q->header();
    initialize();
    query_page();
  }
  elsif($cmd eq 'advanced query')
  {
    print $q->header();
    initialize();
    advanced_query_page();
  }
  elsif($cmd eq 'store query')
  {
    print $q->header();
    initialize();
    store_query();
  }
  elsif($cmd eq 'help')
  {
    print $q->header();
    initialize();
    help_page();
  }
  else
  {
    print $q->header();
    initialize();
    main_page();
  }

  client_exit();
  exit();
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
