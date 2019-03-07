#!/usr/bin/perl

package Server;
use base qw(Net::Server::Multiplex);
use Digest::SHA;use MIME::Base64;
use YAML;
$name=shift(@ARGV);
if($name eq ''){die("No name specified");}

$port=3173;
$base="shady:$port";

if(!-e "data/$name/data.db"){system("./initdb.pl $name");}
use DBI;$db = DBI->connect("dbi:SQLite:dbname=data/$name/data.db","","",{RaiseError=>1},) or die $DBI::errstr;
$dbu = DBI->connect("dbi:SQLite:dbname=data/users.db","","",{RaiseError=>1},) or die $DBI::errstr;

@list=readpipe("ls data/$name/*.yml");
foreach $file(@list){chomp($file);
  $data=readpipe("cat $file");
  $fn=$file;$fn=~s/(.*)\/(.*?)\.(.*)/$2/ig;
  print STDERR "Reading file $file ($fn)\n";
  $config->{$fn}=Load($data);
}scanq();

$|=1;
my $server = bless { server => {proto=>'tcp',port=>$port}, }, 'Server';
$server->run();
exit;

sub mux_connection {
  my $self = shift;
  my $mux  = shift;
  my $fh   = shift;
  my $peer = $self->{peeraddr};
  $self->{id} = $self->{net_server}->{server}->{requests};
  $self->{peerport} = $self->{net_server}->{server}->{peerport};
  print STDERR "DEBUG: Client [$peer] (id $self->{id}) just connected...\n";
  $self->{state} = "header";
}

sub mux_input {
  my $self=shift;my $mux=shift;my $fh=shift;my $in_ref=shift;
  $ck=$self->{peeraddr};$ck=~s/[\.:]//ig;$self->{cookie}=$ck;
  if($self->{state} eq 'login' || $self->{state} eq 'user'){
    while($$in_ref){my $unmask='';
      my $str=$$in_ref;my $type=unpack('H*',substr($str,0,1));my $len=hex(unpack('H*',substr($str,1,1)));my $ll=2;
        if($len>128){$len-=128;if($len==126){
          $len=substr($str,$ll,2);$len=hex(unpack('H*',$len));$ll+=2;
        }elsif($len==127){
          $len=substr($str,$ll,8);$len=hex(unpack('H*',$len));$ll+=8;
        }$mask=substr($str,$ll,4);$ll+=4;
        if(length($$in_ref)>=$len+$ll){$$in_ref=substr($$in_ref,$len+$ll);
          $data=substr($str,$ll,$len);
          my $x=0;while($data){my $c=substr($data,0,1);$data=substr($data,1);
            $unmask.=$c^substr($mask,$x,1);$x++;if($x>3){$x=0;}
          }
          if($type eq "81"){
            ($cmd,$arg)=split(/ /,$unmask,2);
	    print STDERR ">> $cmd $arg\n";
	    if($self->{state} eq 'login'){
	      if($cmd eq 'login'){$arg=~s/[^0-9a-zA-Z\-\.\_]//ig;if($arg ne ''){
	        $u=$dbu->prepare(qq{select id,name,exp,role from user where name=?});
	        $u->execute($arg);if(($id,$n,$e,$r)=$u->fetchrow_array()){
		}else{
		  $dbu->do("insert into user (name) values ('$arg')");
	          $u=$dbu->prepare(qq{select id,name,exp,role from user where name=?});
	          $u->execute($arg);($id,$n,$e,$r)=$u->fetchrow_array();
		}
		$self->{user}=$id;$user{$id}=$n;$exp{$id}=$e;$role{$id}=$r;
		if($state{$id} eq ''){$state{$id}='user';}
		$exp=localtime(time()+3600*24*365);
		print wsoutput("document.cookie='user=$n; expires=$exp';");
		$self->{state}='user';
		userupdate($mux,$id);
	      }}
	    }
	    if($self->{state} eq 'user'){$id=$self->{user};
	      if($cmd eq 'setrole'){
		if($roles{$arg}==1 || $arg eq ''){
		  $role{$id}=$arg;$dbu->do("update user set role='$arg' where id=$id");
		  userupdate($mux,$id);
		}
	      }
	      if($cmd eq 'screen'){
	      	if($arg eq 'entry'){$state{$id}='entry';$userq{$id}='';}
		elsif($arg eq 'view'){$state{$id}='view';$userr{$id}='';}
		elsif($arg eq 'input'){$state{$id}='input';$userq{$id}='';}
		else{$state{$id}='user';}
		userupdate($mux,$id);
	      }
	      if($cmd eq 'report'){my($r,$a)=split(/ /,$arg,2);
	        $userr{$id}=$r;
		if($reportkey{$r} ne ''){$userra{$id}=$a;}else{$userra{$id}='';}
		$userrc{$id}='';
		reportupdate($mux);
	      }
	      if($cmd eq 'input'){
	        my($s,$r)=split(/\./,$arg,2);
	        if($inx{$r}){$userq{$id}=$arg;
		  userupdate($mux,$id);
		}
	      }
	      if($cmd eq 'startupload'){
	        undef $inputbuffer{$id};
	      }
	      if($cmd eq 'endupload'){
	        my @chars=('a'..'z', 0..9);$rnd=join '',map {$chars[rand @chars]} 1..8;
	        if(!-e "data/$name/upload"){system("mkdir \"data/$name/upload\"");}
		while(-e "data/$name/upload/$rnd.jpg"){$rnd++;}
		open(OUT, ">data/$name/upload/$rnd.jpg");print OUT $inputbuffer{$id};close(OUT);
		undef $inputbuffer{$id};
	        foreach my $fh($mux->handles){
		  if($mux->{_fhs}->{$fh}->{object}->{state} eq 'user' && $mux->{_fhs}->{$fh}->{object}->{user}==$id){
		    print $fh wsoutput("changeBox('photo$arg','<input type=hidden id=\"$arg\" name=\"$arg\" value=\"$rnd\"><div style=\"width:4em;height:4em;background-image:url(/img/$rnd.jpg);background-size:cover;background-position:center center;\"></div>');");
		  }
		}
	      }
	      if($cmd eq 'button' && $state{$id} eq 'entry' && $userq{$id}){
  		my ($key,$i)=split(/\./,$userq{$id});
		foreach my $x(keys %$config){
		  if($config->{$x}->{'type'} eq 'question' && $config->{$x}->{'id'} eq $i){$done=0;
		    my $xx=int($arg);my $xxx=0;while($config->{$x}->{'inputs'}->[$xx]->{'do'}->[$xxx]){
		      my $a=keyreplace($config->{$x}->{'inputs'}->[$xx]->{'do'}->[$xxx],$x,$userq{$id});
		      runaction($a);$xxx++;
		    }if($done==1){
		      $e=$config->{$x}->{'expvalue'};$exp{$id}+=$e;$dbu->do("update user set exp=exp+$e where id=$id");
		      $db->do("update question set numleft=numleft-1 where rowid in (select rowid from question where id='".$userq{$id}."' and numleft>0 order by priority asc limit 1)");
		      $userq{$id}='';userupdate($mux,$id);reportupdate($mux);
		    }
		  }
		}
	      }
	      if($cmd eq 'tally' && $state{$id} eq 'entry' && $userq{$id}){
  		my ($key,$i)=split(/\./,$userq{$id});
		foreach my $x(keys %$config){
		  if($config->{$x}->{'type'} eq 'question' && $config->{$x}->{'id'} eq $i){
		    my ($xx,$dir)=split(/ /,$arg);$xx=int($xx);
		    my $s=keyreplace($config->{$x}->{'inputs'}->[$xx]->{'saveas'},$x,$userq{$id});
		    my ($s,$ss)=split(/\./,$s,2);
		    my $vv="val=val+1 where";if($dir eq '-'){$vv="val=val-1 where val>=1 and";}
		    my $u=$db->prepare(qq{update data set $vv id=? and dkey=? and user=?});
		    $u->execute($ss,$s,$id);
		    $u=$db->prepare(qq{select val from data where id=? and dkey=? and user=?});
		    $u->execute($ss,$s,$id);$vv=$u->fetchrow_array();
		    foreach my $fh($mux->handles){
		      if($mux->{_fhs}->{$fh}->{object}->{state} eq 'user' && $mux->{_fhs}->{$fh}->{object}->{user}==$id){
		        print $fh wsoutput("changeBox('tally$xx','$vv');");
		      }
		    }
		  }
		}
	      }
	      if($cmd eq 'submit' && ($state{$id} eq 'entry' || $state{$id} eq 'input') && $userq{$id}){
	        my ($kk,$iii)=split(/\./,$userq{$id});
		foreach my $x(keys %$config){
		  if(($config->{$x}->{'type'} eq 'question' || $config->{$x}->{'type'} eq 'input') && $config->{$x}->{'id'} eq $iii){
		    @in=split(/ /,$arg);undef %val;
		    my $xx=0;while($config->{$x}->{'inputs'}->[$xx]){
		      if($config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'text' || $config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'list' || $config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'picture'){
		        my $in='';my $ii=shift(@in);while(@in && $ii ne "\$\$val$xx\$\$"){$in.=$ii.' ';$ii=shift(@in);}chop($in);
			$val{"val$xx"}=$in;
			if($config->{$x}->{'inputs'}->[$xx]->{'saveas'}){my $s=keyreplace($config->{$x}->{'inputs'}->[$xx]->{'saveas'},$x,$userq{$id});
	  		  my ($key,$i)=split(/\./,$s);
		          my $u=$db->prepare(qq{insert into datas (id,dkey,user,val) values (?,?,?,?)});
		          $u->execute($i,$key,$id,$in);
			}
		      }elsif($config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'number'){
		        my $in='';my $ii=shift(@in);while(@in && $ii ne "\$\$val$xx\$\$"){$in.=$ii.' ';$ii=shift(@in);}chop($in);
			$val{"val$xx"}=$in;
			if($config->{$x}->{'inputs'}->[$xx]->{'saveas'}){my $s=keyreplace($config->{$x}->{'inputs'}->[$xx]->{'saveas'},$x,$userq{$id});
	  		  my ($key,$i)=split(/\./,$s);
		          my $u=$db->prepare(qq{insert into data (id,dkey,user,val) values (?,?,?,?)});
		          $u->execute($i,$key,$id,$in);
			}
		      }elsif($config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'tally'){
		        my $s=keyreplace($config->{$x}->{'inputs'}->[$xx]->{'saveas'},$x,$userq{$id});
			my ($key,$i)=split(/\./,$s);
			my $u=$db->prepare(qq{update data set visible=1 where id=? and dkey=? and user=?});
			$u->execute($i,$key,$id);
		      }elsif($config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'submit'){
		        if($config->{$x}->{'inputs'}->[$xx]->{'do'}){
		          my $xxx=0;while($config->{$x}->{'inputs'}->[$xx]->{'do'}->[$xxx]){
			    my $a=keyreplace($config->{$x}->{'inputs'}->[$xx]->{'do'}->[$xxx],$x,$userq{$id});
			    foreach my $v(keys %val){my $vv=$val{$v};$a=~s/\$\$$v\$\$/$vv/ig;}
			    runaction($a);$xxx++;
		 	  }
		        }
		      }
		    $xx++;}
		    if($config->{$x}->{'type'} eq 'question'){
		      $e=$config->{$x}->{'expvalue'};$exp{$id}+=$e;$dbu->do("update user set exp=exp+$e where id=$id");
		      $db->do("update question set numleft=numleft-1 where rowid in (select rowid from question where id='".$userq{$id}."' and numleft>0 order by priority asc limit 1)");
		    }
		    $userq{$id}='';userupdate($mux,$id);reportupdate($mux);
		  }
		}
	      }
	    }
          }elsif($type==82){
	    if($self->{state} eq 'user'){$id=$self->{user};
	      $inputbuffer{$id}.=$unmask;
	      print STDERR "Upload data chunk received (".length($inputbuffer{$id}).")\n";
	    }
	  }
        }else{$$in_ref='';}
      }else{$$in_ref='';}
    }
  }while ($$in_ref =~ s/^(.*?)\r?\n//){
    my $msg=$1;#print STDERR ">> $msg\n";
    if($self->{state} eq 'header'){
      if($msg eq ''){
	$self->{page}='';$_=$self->{header};
	if(/GET \/([a-z0-9\.\/]*)/ig){$self->{page}=lc($1);}
	$_=$self->{header};
	if(/Upgrade: websocket/ig){
	  $_=$self->{header};if(/Sec-WebSocket-Key: (.*?)\r?\n/ig){$key=$1;
	    $m="HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n";
	    $hash=Digest::SHA::sha1($key.'258EAFA5-E914-47DA-95CA-C5AB0DC85B11');
	    $enc=encode_base64($hash);chomp($enc);
	    $m.="Sec-WebSocket-Accept: $enc\r\nConnection: Upgrade\r\n\r\n";
	    print $m;
	    $_=$self->{header};
	    if(/Cookie:(.*?)user=([0-9a-z\-\.\_]*?)['" ;\r\n]/ig){
	      $u=$dbu->prepare(qq{select id,name,exp,role from user where name=?});
	      $u->execute($2);if(($id,$n,$e,$r)=$u->fetchrow_array()){
		$self->{user}=$id;$user{$id}=$n;$exp{$id}=$e;$role{$id}=$r;
		if($state{$id} eq ''){$state{$id}='user';}
		$self->{state}='user';
		userupdate($mux,$id);
	      }
	    }if($self->{state} eq 'header'){
	      $m="<div style=\"font-size:'+ht(8)+'px;text-align:center;\">Enter your username to continue<br><input style=\"font-size:'+ht(8)+'px;\" type=\"text\" id=\"uname\" size=\"20\"><br>";
	      $m.="<input style=\"font-size:'+ht(8)+'px;\" type=\"button\" value=\"Submit\" onClick=\"sendData(\\\'login \\\'+document.getElementById(\\\'uname\\\').value);\"></div>";
	      print wsoutput("changeBox('main','$m');");
	      $self->{state}='login';
	    }
	  }
	}elsif(/Upgrade: datasource/ig){
	  $self->{state}='source';
	}elsif(substr($self->{page},0,4) eq 'img/'){my $m='';$file=substr($self->{page},4);$file=~s/[^0-9a-z\.]//g;
	  print STDERR "Sending image $file\n";
	  if(-e "data/$name/upload/$file"){$m=readpipe("cat \"data/$name/upload/$file\"");}
	  print "HTTP/1.1 200 Here you go\r\n";
	  print "Server: WS_bcast_data/0.1.0\r\nCache-Control: no-cache\r\nConnection: close\r\nContent-length: ".length($m)."\r\nContent-type: image/jpeg\r\n\r\n";
	  print $m;
	  forceclose($mux,$mux->{_fhs}->{$fh}->{object}->{id});
	}else{
	  print_page();forceclose($mux,$mux->{_fhs}->{$fh}->{object}->{id});
	}
      }else{
        $self->{header}.=$msg."\n";
      }
    }
  }
}

sub userupdate{my $mux=shift(@_);my $id=shift(@_);my $m='';my $doq=0;
  scanq();
  $m.="<div style=\"font-size:'+ht(12)+'px;position:absolute;top:0;left:0;width:100%;height:10%;border-bottom-style:solid;border-bottom-width:1px;\">";
  $m.="<div style=\"position:absolute;top:0;left:5%;\">".$user{$id}."</div>";
  my $x=$exp{$id};my $n=10;my $l=1;
  while($x>=$n){$x-=$n;$l++;$n+=10;};$level{$id}=$l;
  $m.="<div style=\"position:absolute;top:0;left:30%;\">Level $l</div>";
  $m.="<div style=\"position:absolute;top:0;left:55%;\">$x/$n Exp</div>";
  $m.="<div style=\"position:absolute;top:0;left:80%;\">".$role{$id}."</div>";
  $m.="</div>";
  $m.="<div style=\"position:absolute;top:15%;left:2%;width:5%;height:12%;border-style:solid;border-width:1px;\" onClick=\"sendData(\\\'screen user\\\');\"><table border=0 width=100% height=100%><tr><td align=center valign=center style=\"font-size:'+ht(12)+'px;\">&#9881;</td></tr></table></div>";
  $m.="<div style=\"position:absolute;top:30%;left:2%;width:5%;height:12%;border-style:solid;border-width:1px;\" onClick=\"sendData(\\\'screen entry\\\');\"><table border=0 width=100% height=100%><tr><td align=center valign=center style=\"font-size:'+ht(12)+'px;\">&#9999;</td></tr></table></div>";
  $m.="<div style=\"position:absolute;top:45%;left:2%;width:5%;height:12%;border-style:solid;border-width:1px;\" onClick=\"sendData(\\\'screen view\\\');\"><table border=0 width=100% height=100%><tr><td align=center valign=center style=\"font-size:'+ht(12)+'px;\">&#8505;</td></tr></table></div>";
  my $go=0;foreach my $x(keys %inx){if($l>=$inxlvl{$x}){$go=1;}}if($go==1){
    $m.="<div style=\"position:absolute;top:60%;left:2%;width:5%;height:12%;border-style:solid;border-width:1px;\" onClick=\"sendData(\\\'screen input\\\');\"><table border=0 width=100% height=100%><tr><td align=center valign=center style=\"font-size:'+ht(12)+'px;\">&#9993;</td></tr></table></div>";
  }
  $m.="<div style=\"position:absolute;top:15%;left:10%;width:88%;height:83%;overflow:auto;font-size:'+ht(10)+'px;\" id=\"mainview\">";
  if($state{$id} eq 'entry'){
    if($userq{$id} eq ''){$m.="Please wait...";}else{$m.=questiondata($userq{$id},$id);}
  }elsif($state{$id} eq 'view'){$m.="<ul>";
    foreach my $x(keys %report){
      if($l>=$reportlvl{$x} && ($reportrole{$x} eq $role{$id} || $reportrole{$x} eq "")){
        $m.="<li>".$report{$x}." ";
	if($reportkey{$x} ne ''){my $v;
	  $m.="<select style=\"font-size:'+ht(15)+'px;\" id=key$x>";
	  my $u=$db->prepare(qq{select val from datas where id=? and dkey=? and visible=1});
	  $u->execute($reportkey{$x},'');while($v=$u->fetchrow_array()){$m.="<option value=\"$v\">$v</option>";}
	  $m.="</select> ";
	  $m.="<input type=button style=\"font-size:'+ht(15)+'px;\" value=\"View\" onClick=\"sendData(\\\'report $x \\\'+document.getElementById(\\\'key$x\\\').value);\">";
	}else{
	  $m.="<input type=button style=\"font-size:'+ht(15)+'px;\" value=\"View\" onClick=\"sendData(\\\'report $x\\\');\">";
	}$m.="</li>";
      }
    }
  }elsif($state{$id} eq 'input'){
    if($userq{$id} eq ''){
      $m.="<ul>";
      foreach my $x(keys %inx){
        if($l>=$inxlvl{$x} && ($inxrole{$x} eq $role{$id} || $inxrole{$x} eq "")){
          $m.="<li>".$inx{$x}." ";
	  if($inxkey{$x} ne ''){my $v;
	    $m.="<select style=\"font-size:'+ht(15)+'px;\" id=key$x>";
	    my $u=$db->prepare(qq{select val from datas where id=? and dkey=? and visible=1});
	    $u->execute($inxkey{$x},'');while($v=$u->fetchrow_array()){$m.="<option value=\"$v\">$v</option>";}
	    $m.="</select> ";
	    $m.="<input type=button style=\"font-size:'+ht(15)+'px;\" value=\"Enter Data\" onClick=\"sendData(\\\'input \\\'+document.getElementById(\\\'key$x\\\').value+\\\'.$x\\\');\">";
	  }else{
	    $m.="<input type=button style=\"font-size:'+ht(15)+'px;\" value=\"Enter Data\" onClick=\"sendData(\\\'input .$x\\\');\">";
	  }$m.="</li>";
        }
      }
    }else{
      $m.=questiondata($userq{$id},$id);
    }
  }else{
    $m.=$user{$id}." ($id) ";
    $m.="<input type=button style=\"font-size:'+ht(15)+'px;float:right;\" value=\"Logout\" onClick=\"document.cookie=\\\'user=\\\';location.href=\\\'/\\\';\">";
    if($l>=2){$m.="<br><div id=usercnt style=\"margin-top:0.5ex;\"></div>";}
    if($l>=1){$m.="<br><select style=\"font-size:'+ht(15)+'px;\" id=setrole><option value=\"\"></option>";
      foreach my $x(keys %roles){$m.="<option value=\"$x\">$x</option>";}
      $m.="</select> <input type=button style=\"font-size:'+ht(15)+'px;\" value=\"Set Role\" onClick=\"sendData(\\\'setrole \\\'+document.getElementById(\\\'setrole\\\').value);\">";
    }
  }
  $m.="</div>";

  foreach my $fh($mux->handles){
    if($mux->{_fhs}->{$fh}->{object}->{state} eq 'user' && $mux->{_fhs}->{$fh}->{object}->{user}==$id){
      print $fh wsoutput("changeBox('main','$m');");
    }
  }
  newquestions($mux);
  userstats($mux);
}

sub reportdata{my $rr=shift(@_);my $key=shift(@_);
  foreach my $x(keys %$config){
    if($config->{$x}->{'type'} eq 'report' && $config->{$x}->{'id'} eq $rr){
      return keyreplace($config->{$x}->{'output'},$x,$key);
    }
  }
}

sub questiondata{my $q=shift(@_);my $uid=shift(@_);my $m='';
  my ($key,$id)=split(/\./,$q);@k=split(/:/,$key);
  foreach my $x(keys %$config){
    if(($config->{$x}->{'type'} eq 'question' || $config->{$x}->{'type'} eq 'input') && $config->{$x}->{'id'} eq $id){undef @sub;
      my $xx=0;while($config->{$x}->{'inputs'}->[$xx]){
	if($config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'label'){
	  $m.="<div style=\"font-size:'+ht(10)+'px;".$config->{$x}->{'inputs'}->[$xx]->{'style'}."\">";
	  $m.=$config->{$x}->{'inputs'}->[$xx]->{'label'}."</div>";
	}elsif($config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'text'){
	  $m.=$config->{$x}->{'inputs'}->[$xx]->{'label'}.' ';
	  $m.="<input style=\"font-size:'+ht(10)+'px;".$config->{$x}->{'inputs'}->[$xx]->{'style'}."\" type=text id=val$xx>";
	  push(@sub, "val$xx");
	}elsif($config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'list'){
	  $m.=$config->{$x}->{'inputs'}->[$xx]->{'label'}.' ';
	  $m.="<select style=\"font-size:'+ht(10)+'px;".$config->{$x}->{'inputs'}->[$xx]->{'style'}."\" id=val$xx>";
	  my $l=$config->{$x}->{'inputs'}->[$xx]->{'listdata'};
	  my $u=$db->prepare(qq{select val from datas where id=? and dkey='' and visible=1 order by val asc});
	  $u->execute($l);while($l=$u->fetchrow_array()){$m.="<option value=\"$l\">$l</option>";}
	  $m.="</select>";push(@sub, "val$xx");
	}elsif($config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'number'){
	  $m.=$config->{$x}->{'inputs'}->[$xx]->{'label'}.' ';
	  $m.="<input style=\"font-size:'+ht(10)+'px;".$config->{$x}->{'inputs'}->[$xx]->{'style'}."\" type=number id=val$xx>";
	  push(@sub, "val$xx");
	}elsif($config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'picture'){
	  $m.=$config->{$x}->{'inputs'}->[$xx]->{'label'}.' ';
	  $m.="<div id=\"photoval$xx\"><div id=\"status$xx\"></div><div id=\"in$xx\"><input style=\"font-size:'+ht(10)+'px;".$config->{$x}->{'inputs'}->[$xx]->{'style'}."\" type=\"file\" accept=\"image/*\" capture=\"camera\" id=\"val$xx\" onChange=\"setTimeout(\\\'document.getElementById(\\\\\\\'inx$xx\\\\\\\').click();\\\',500);\"><br>";
	  $m.="<input style=\"font-size:'+ht(10)+'px;".$config->{$x}->{'inputs'}->[$xx]->{'style'}."\" type=\"button\" value=\"Upload Image\" id=\"inx$xx\" onClick=\"";
	  $m.="document.getElementById(\\\'in$xx\\\').style.display=\\\'hidden\\\';";
	  $m.="r=new FileReader();r.readAsDataURL(document.getElementById(\\\'val$xx\\\').files[0]);";
	  $m.="r.onload=function(evt){i=new Image();i.src=r.result;";
	  $m.="w=i.width;h=i.height;if(w>h && w>1000){h*=1000/w;w=1000;}else if(h>w && h>1000){w*=1000/h;h=1000;}";
	  $m.="c=document.createElement(\\\'canvas\\\');c.width=w;c.height=h;c.getContext(\\\'2d\\\').drawImage(i,0,0,w,h);";
	  $m.="setTimeout(\\\'c.toBlob(function(b){var x=0;var e=b.size;sendData(\\\\\\\'startupload\\\\\\\');";
	  $m.="while(x<e){var xx=x+1024;if(xx>e){xx=e;}sendData(b.slice(x,xx));x=xx;changeBox(\\\\\\\'status$xx\\\\\\\',\\\\\\\'Uploading - \\\\\\\'+xx+\\\\\\\'/\\\\\\\'+e);}";
  	  $m.="sendData(\\\\\\\'endupload val$xx\\\\\\\');},\\\\\\\'image/jpeg\\\\\\\');\\\',1000);};\"></div></div>";
	  push(@sub, "val$xx");
	}elsif($config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'button'){
	  $m.="<input style=\"font-size:'+ht(10)+'px;".$config->{$x}->{'inputs'}->[$xx]->{'style'}."\" type=button ";
	  $m.="value=\"".$config->{$x}->{'inputs'}->[$xx]->{'label'}."\" onClick=\"sendData(\\\'button $xx\\\');\">";
	}elsif($config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'tally'){
	  $m.="<div style=\"font-size:'+ht(10)+'px;text-align:center;".$config->{$x}->{'inputs'}->[$xx]->{'style'}."\">";
	  $m.="<input type=button style=\"font-size:'+ht(10)+'px;float:left;\" value=\"+\" onClick=\"sendData(\\\'tally $xx +\\\');\">";
	  my $s=keyreplace($config->{$x}->{'inputs'}->[$xx]->{'saveas'},$x,$key);
	  my ($s,$ss)=split(/\./,$s,2);my $v;my $vv;
	  my $u=$db->prepare(qq{select added,val from data where id=? and dkey=? and user=?});
	  $u->execute($ss,$s,$uid);if(($vv,$v)=$u->fetchrow_array()){}else{
	    $u=$db->prepare(qq{insert into data (id,dkey,user,val,visible) values (?,?,?,?,0)});
	    $u->execute($ss,$s,$uid,0);$v=0;
	  }
	  $m.=$config->{$x}->{'inputs'}->[$xx]->{'label'}." - <span id=tally$xx>$v</span>";
	  $m.="<input type=button style=\"font-size:'+ht(10)+'px;float:right;\" value=\"-\" onClick=\"sendData(\\\'tally $xx -\\\');\">";
	  $m.="</div>";
	}elsif($config->{$x}->{'inputs'}->[$xx]->{'type'} eq 'submit'){
	  $m.="<input style=\"font-size:'+ht(10)+'px;".$config->{$x}->{'inputs'}->[$xx]->{'style'}."\" type=button ";
	  $m.="value=\"".$config->{$x}->{'inputs'}->[$xx]->{'label'}."\" onClick=\"sendData(\\\'submit";
	  while(@sub){my $v=shift(@sub);$m.=" \\\'+document.getElementById(\\\'$v\\\').value+\\\' \$\$$v\$\$";}
	  $m.="\\\');\">";
	}
      $xx++;}
      return keyreplace($m,$x,$key);
    }
  }
}

sub runaction{my $a=shift(@_);
  my ($c,$a)=split(/ /,$a,2);
  if($c eq 'addquestion'){
    $db->do("update question set numleft=1 where id='$a' and numleft<=1");
  }
  if($c eq 'addtextdata'){
    my ($ki,$d)=split(/ /,$a,2);my ($k,$i)=split(/\./,$ki,2);
    my $u=$db->prepare(qq{insert into datas (id,dkey,user,val) values (?,?,?,?)});
    $u->execute($i,$k,$id,$d);
  }
  if($c eq 'addnumdata'){
    my ($ki,$d)=split(/ /,$a,2);my ($k,$i)=split(/\./,$ki,2);
    my $u=$db->prepare(qq{insert into data (id,dkey,user,val) values (?,?,?,?)});
    $u->execute($i,$k,$id,$d);
  }
  if($c eq 'delay'){
    my ($q,$t)=split(/ /,$a,2);
    $db->do("update question set waituntil=datetime('now','+$t') where id='$q'");
  }
  if($c eq 'eval'){eval($a);}
  if($c eq 'markdone'){$done=1;}
}

sub keyreplace{my $m=shift(@_);my $x=shift(@_);my $kkk=shift(@_);my $early=shift(@_);my $ek=shift(@_);
  my ($kkk,@k)=split(/\./,$kkk);@k=split(/:/,$kkk);
  my $k=$config->{$x}->{'key'};my @kk=split(/:/,$k);if($ek){push(@kk,$ek);}
  while(@kk){my $a=shift(@k);my $b=shift(@kk);
    $m=~s/\$\$$b\$\$/$a/ig;
  }
  if($early>0){return $m;}
  my $xx=0;while($config->{$x}->{'variables'}->[$xx]){
    my $b=$config->{$x}->{'variables'}->[$xx]->{'name'};
    my $a=getvar($x,$config->{$x}->{'variables'}->[$xx],$kkk);
    $m=~s/\$\$$b\$\$/$a/ig;
  $xx++;}
  return $m;
}

sub getvar{my $x=shift(@_);my $xx=shift(@_);my $kkk=shift(@_);my $ek=shift(@_);my $a='';
  if($xx->{'type'} eq 'string'){
    my $s=keyreplace($xx->{'source'},$x,$kkk,1,$ek);
    my ($s,$ss)=split(/\./,$s,2);
    my $u=$db->prepare(qq{select val from datas where id=? and dkey=? and visible=1 order by added desc limit 1});
    $u->execute($ss,$s);$a=$u->fetchrow_array();
  }elsif($xx->{'type'} eq 'count'){
    my $s=keyreplace($xx->{'source'},$x,$kkk,1,$ek);
    my ($s,$ss)=split(/\./,$s,2);
    my $ex='';if($xx->{'filter'}){$ex="and ".keyreplace($xx->{'filter'},$x,$kkk,1,$ek);}
    my $u=$db->prepare(qq{select count(distinct dkey) from data where id=? and dkey like ? and visible=1 $ex});
    $u->execute($ss,$s);$a=$u->fetchrow_array();
  }elsif($xx->{'type'} eq 'stringcount'){
    my $s=keyreplace($xx->{'source'},$x,$kkk,1,$ek);
    my ($s,$ss)=split(/\./,$s,2);
    my $ex='';if($xx->{'filter'}){$ex="and ".keyreplace($xx->{'filter'},$x,$kkk,1,$ek);}
    my $u=$db->prepare(qq{select count(distinct dkey) from datas where id=? and dkey like ? and visible=1 $ex});
    $u->execute($ss,$s);$a=$u->fetchrow_array();
  }elsif($xx->{'type'} eq 'average'){
    my $s=keyreplace($xx->{'source'},$x,$kkk,1,$ek);
    my ($s,$ss)=split(/\./,$s,2);
    my $ex='';if($xx->{'filter'}){$ex="and ".keyreplace($xx->{'filter'},$x,$kkk,1,$ek);}
    my $u=$db->prepare(qq{select dkey,avg(val) from data where id=? and dkey like ? and visible=1 $ex group by dkey});
    $u->execute($ss,$s);$a=0;my $c=0;my $v;
    while(($ex,$v)=$u->fetchrow_array()){$c++;$a+=$v;}
    if($c>0){$a=$a/$c;}
  }elsif($xx->{'type'} eq 'sum'){
    my $s=keyreplace($xx->{'source'},$x,$kkk,1,$ek);
    my ($s,$ss)=split(/\./,$s,2);
    my $ex='';if($xx->{'filter'}){$ex="and ".keyreplace($xx->{'filter'},$x,$kkk,1,$ek);}
    my $u=$db->prepare(qq{select dkey,avg(val) from data where id=? and dkey like ? and visible=1 $ex group by dkey});
    $u->execute($ss,$s);$a=0;my $c=0;my $v;
    while(($ex,$v)=$u->fetchrow_array()){$c++;$a+=$v;}
  }elsif($xx->{'type'} eq 'sql'){$a=0;
  }elsif($xx->{'type'} eq 'commentlist'){$a="<ul>";
    my $s=keyreplace($xx->{'source'},$x,$kkk,1,$ek);
    my ($s,$ss)=split(/\./,$s,2);my $us;my $ad;my $v;
    my $u=$db->prepare(qq{select user,added,val from datas where id=? and dkey=? and visible=1 order by added desc});
    $u->execute($ss,$s);while(($us,$ad,$v)=$u->fetchrow_array()){
      if(!$user{$us}){my $uu=$dbu->prepare(qq{select name from user where id=?});$uu->execute($us);$user{$us}=$uu->fetchrow_array();}
      $a.="<li>$ad - ".$user{$us}." - $v</li>";
    }$a.="</ul>";
  }elsif($xx->{'type'} eq 'userlist'){$a="<table border=1><tr><th>User</th><th>Exp</th><th>Role</th></tr>";
    my $u=$dbu->prepare(qq{select name,exp,role from user order by exp desc});
    $u->execute();while(($un,$ue,$ur)=$u->fetchrow_array()){
      $a.="<tr><td>$un</td><td>$ue</td><td>$ur</td></tr>";
    }$a.="</table>";
  }elsif($xx->{'type'} eq 'table'){
    my $dbm=DBI->connect("dbi:SQLite:dbname=:memory:");
    my $t="create table temp (".$xx->{'key'}." varchar(64)";
    $a="<table border=1><tr><th>".$xx->{'keytitle'}."</th>";
    my $c=0;while($xx->{'columns'}->[$c]){
      $a.="<th>".$xx->{'columns'}->[$c]->{'title'}."</th>";
      my $tt="integer";if($xx->{'columns'}->[$c]->{'type'} eq 'string'){$tt="varchar(255)";}
      elsif($xx->{'columns'}->[$c]->{'type'} eq 'sql'){$tt="float";}
      $t.=", ".$xx->{'columns'}->[$c]->{'name'}." $tt";
    $c++;}
    $a.="</tr>";$t.=")";$dbm->do($t);
    my $s=keyreplace($xx->{'source'},$x,$kkk,1);
    my ($s,$ss)=split(/\./,$s,2);
    my $u=$db->prepare(qq{select val from datas where id=? and dkey=? and visible=1});
    $u->execute($ss,$s);while($t=$u->fetchrow_array()){my @dd;push(@dd,$t);my $ke=$kkk;if($ke ne ''){$ke.=":";}$ke.=$t;
      my $c=0;while($xx->{'columns'}->[$c]){push(@dd,getvar($x,$xx->{'columns'}->[$c],$ke,$xx->{'key'}));$c++;}
      $t='';foreach $c(@dd){$t.="'$c',";}chop($t);$dbm->do("insert into temp values ($t)");
    }
    my $c=0;while($xx->{'columns'}->[$c]){if($xx->{'columns'}->[$c]->{'type'} eq 'sql'){
      my $ex='';if($xx->{'columns'}->[$c]->{'filter'}){$ex=" where ".$xx->{'columns'}->[$c]->{'filter'};}
      $dbm->do("update temp set ".$xx->{'columns'}->[$c]->{'name'}."=".$xx->{'columns'}->[$c]->{'source'}.$ex);
    }$c++;}
    $t=$xx->{'order'};
    my $ex='';if($xx->{'filter'}){$ex="where ".keyreplace($xx->{'filter'},$x,$kkk,1,$ek);}
    my $u=$dbm->prepare(qq{select * from temp $ex order by $t});
    $u->execute();my @dd;while(@dd=$u->fetchrow_array()){$a.="<tr>";foreach $t(@dd){$a.="<td>$t</td>";}$a.="</td>";}
    $a.="</table>";
    $u->finish();$dbm->disconnect();
  }return $a;
}

sub reportupdate{my $mux=shift(@_);
  foreach my $u(keys %state){if($state{$u} eq 'view' && $userr{$u} ne ''){
    my $m=reportdata($userr{$u},$userra{$u});
    if($m ne $userrc{$u}){$userrc{$u}=$m;
      foreach my $fh($mux->handles){
        if($mux->{_fhs}->{$fh}->{object}->{state} eq 'user' && $mux->{_fhs}->{$fh}->{object}->{user}==$u){
          print $fh wsoutput("changeBox('mainview','$m');");
        }
      }
    }
  }}
}

sub newquestions{my $mux=shift(@_);
  foreach my $u(keys %state){if($state{$u} eq 'entry' && !$userq{$u}){
    my $x=0;$go=0;while($x<=$#questions && $go==0){$go=1;
      if($role{$u} ne '' && $role{$u} ne $roles[$x]){$go=0;}
      if($go==1 && $alreadydone{"$u-".$questions[$x]}==1){$go=0;}
      if($go==1){my ($k,$i)=split(/\./,$questions[$x]);
        my $u=$db->prepare(qq{select val from datas where id=? and dkey=? and user=?});
	$u->execute($i,$k,$u);if($u->fetchrow_array()){$go=0;$alreadydone{"$u-".$questions[$x]}=1;}
      }
      if($go==0){$x++;}
    }if($go==1){
      $userq{$u}=$questions[$x];
      splice(@questions,$x,1);splice(@roles,$x,1);
      my $m=questiondata($userq{$u},$u);
      foreach my $fh($mux->handles){
        if($mux->{_fhs}->{$fh}->{object}->{state} eq 'user' && $mux->{_fhs}->{$fh}->{object}->{user}==$u){
          print $fh wsoutput("changeBox('mainview','$m');");
        }
      }
    }
  }}
}

sub scanq{my $ch=0;my $id;
  foreach my $x(keys %$config){
    if($config->{$x}->{'type'} eq 'list'){
      my $u=$db->prepare(qq{select added from datas where id=? and dkey='' and val=?});
     $id=$config->{$x}->{'id'};$i=0;while($config->{$x}->{'populate'}->[$i]){
        $dd=$config->{$x}->{'populate'}->[$i];
        $u->execute($id,$dd);
        if($u->fetchrow_array()){}else{$db->do("insert into datas (id,dkey,val) values ('$id','','$dd');");$ch++;}
        $i++;
      }
    }if($config->{$x}->{'type'} eq 'question'){
      $id=$config->{$x}->{'id'};$role=$config->{$x}->{'role'};$roles{$role}=1;
      $num=$config->{$x}->{'dataneeded'};$p=$config->{$x}->{'priority'};
      $key=$config->{$x}->{'key'};@key=split(/:/,$key);
      genq($id,'',@key);
    }if($config->{$x}->{'type'} eq 'report'){
      $report{$config->{$x}->{'id'}}=$config->{$x}->{'title'};
      $reportkey{$config->{$x}->{'id'}}=$config->{$x}->{'key'};
      $reportlvl{$config->{$x}->{'id'}}=$config->{$x}->{'reqlevel'};
	  $reportrole{$config->{$x}->{'id'}}=$config->{$x}->{'role'};
    }if($config->{$x}->{'type'} eq 'input'){
      $inx{$config->{$x}->{'id'}}=$config->{$x}->{'title'};
      $inxkey{$config->{$x}->{'id'}}=$config->{$x}->{'key'};
      $inxlvl{$config->{$x}->{'id'}}=$config->{$x}->{'reqlevel'};
	  $inxrole{$config->{$x}->{'id'}}=$config->{$x}->{'role'};
    }
  }
  if($ch>0){scanq();}else{undef @questions;undef @roles;
    my $u=$db->prepare(qq{select id,role,numleft from question where numleft>0 and waituntil<=datetime('now') order by priority asc,random()});
    $u->execute();while(($i,$r,$c)=$u->fetchrow_array()){
      foreach my $x(keys %userq){if($state{$x} eq 'entry' && $userq{$x} eq $i){$c--;}}
      while($c>=1){push(@questions,$i);push(@roles,$r);$c--;}
    }
  }
}

sub genq{my $id=shift(@_);my $m=shift(@_);my @k=@_;
  if(@k){
    my $x=shift(@k);my $xx;
    my $u=$db->prepare(qq{select val from datas where id=? and dkey=''});
    $u->execute($x);while($xx=$u->fetchrow_array()){my $mm=$m;
      if($mm ne ''){$mm.=":";}$mm.=$xx;genq($id,$mm,@k);
    }
  }else{
    my $u=$db->prepare(qq{select id from question where id=?});
    $u->execute("$m.$id");if($u->fetchrow_array()){}else{
      $db->do("insert into question (id,numleft,waituntil,priority,role) values ('$m.$id','$num',datetime('now'),'$p','$role')");$ch++;
    }
  }
}

sub userstats{my $mux=shift(@_);my %x;my $tot=0;my $uu=0;my $ue=0;my $uv=0;
  foreach my $fh($mux->handles){
    if($mux->{_fhs}->{$fh}->{object}->{state} eq 'user'){
      my $u=$mux->{_fhs}->{$fh}->{object}->{user};if($x{$u}!=1){$x{$u}=1;
        if($state{$u} eq 'entry'){$ue++;}elsif($state{$u} eq 'view'){$uv++;}else{$uu++;}$tot++;
      }
    }
  }
  foreach my $fh($mux->handles){
    if($mux->{_fhs}->{$fh}->{object}->{state} eq 'user'){
      my $u=$mux->{_fhs}->{$fh}->{object}->{user};if($state{$u} eq 'user' && $level{$u}>=2){
        print $fh wsoutput("changeBox('usercnt','$tot Users ($uu user, $ue entry, $uv view)');");
      }
    }
  }
}

sub wsoutput{my $line=shift(@_);
  print STDERR "<< $line\n";
  my $len=length($line);my $pre='';
  my $ll=sprintf('%x',$len);
  if($len<126){
    while(length($ll)<2){$ll="0".$ll;}
  }elsif($len<=65536){
    $pre='7E';while(length($ll)<4){$ll="0".$ll;}
  }else{
    $pre='7F';while(length($ll)<16){$ll="0".$ll;}
  }$ll=pack('H*',$pre.$ll);
  return "\x81".$ll.$line;
}

sub forceclose{my $mux=shift(@_);my $i=shift(@_);
    foreach my $fh($mux->handles){
      if($mux->{_fhs}->{$fh}->{object}->{id} == $i){
	$mux->shutdown($fh,2);
      }
    }
}

sub mux_close {
  my $self = shift;
  my $mux  = shift;
  my $fh   = shift;
  my $peer = $self->{peeraddr};
  if (exists $self->{id}) {
    print STDERR "DEBUG: Client [$peer] (id $self->{id}) closed connection!\n";
  }
  $self->{status}="closed";
  userstats($mux);
}

sub print_page{
 print "HTTP/1.1 200 Here you go\r\n";
 print "Server: WS_bcast_data/0.1.0\r\nCache-Control: no-cache\r\nConnection: close\r\nContent-type: text/html\r\n\r\n";
 print <<EOF
<html><head><title>Data Collection</title>
<script language="Javascript">
  var websocket;
  function retry(){try{
EOF
;print "websocket = new WebSocket(\"ws://$base\");\n";
print <<EOF
    websocket.onclose = function(evt){setTimeout('retry();',1000);};
    websocket.onmessage = function(evt){eval(evt.data);};
    }catch(err){}
  }
  function sendData(x){
    websocket.send(x);
  }
  function changeBox(x,data){
    if(document.getElementById(x)){
      document.getElementById(x).innerHTML=data;
    }
  }
  function ht(x){
    return (document.body.clientHeight-50)/x;
  }
  var lcnt=0;
  var html=document.getElementsByTagName("head").item(0);
</script></head><body bgcolor="#000000" text="#FFFFFF" onLoad="retry();">
<div style="width:100%;height:100%;margin:0;padding:0;position:absolute;top:0;left:0;" id="main"></div>
<div style="width:1px;height:1px;position:absolute;top:0;left:0;overflow:hidden;" id="preload"></div>
<div style="width:100%;height:15%;position:absolute;top:-15%;left:0;" id="extra"></div>
</body></html>
EOF
;
}
