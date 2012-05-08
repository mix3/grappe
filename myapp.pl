#!/usr/bin/env perl
use Mojolicious::Lite;
use Digest::MD5 'md5_hex';
use utf8;

# Documentation browser under "/perldoc"
plugin 'PODRenderer';

my $config = {
    type => {
        line   => { type => 'Line',   name => '折れ線' },
        column => { type => 'Column', name => '棒'     },
    },
};

my $tmp = app->home->rel_dir('tmp');
mkdir($tmp);

# index
get '/' => sub {
    my $self = shift;
    $self->render(config => $config);
} => 'index';

# graph
get '/:type/:key' => sub {
    my $self = shift;

    my $type = $self->param('type');
    my $key  = $self->param('key');
    my $path = "$tmp/$key";

    unless (defined $config->{type}->{$type}) {
        return $self->render_not_found;
    }

    unless (-f $path) {
        return $self->render_not_found;
    }

    my $result = _get({ type => $type, key => $key });

    unless ($result) {
        return $self->render_not_found;
    }

    my $columns = [];
    my $rows    = [];

    my $i = 0;
    for my $line (split(/\r?\n/, $result)) {
        my @data = split(/\s/, $line);
        unless ($i++) {
            $columns = \@data;
        } else {
            $data[0] = "'".$data[0]."'";
            push @$rows, \@data;
        }
    }

    $self->render(
        config => $config,
        size => {
            w => $self->param('w') || 800,
            h => $self->param('h') || 800,
        },
        columns => $columns,
        rows    => $rows,
        type    => $type || 'Line',
    );
} => 'graph';

# create api
# update api
under sub {
    my $self = shift;

    my $result = _create_or_update($self->req->params->to_hash);

    if ($result->{error}) {
        return $self->render_exception(
            $result->{message}
        );
    }

    $self->redirect_to('/'.$result->{type}.'/'.$result->{key});
};

post '/';

post '/:type';

post '/:type/:key';

sub _create_or_update {
    my $args = shift;

    unless ($args->{type} && $args->{input}) {
        return { error => 1, message => 'require param: type, input' };
    }

    unless (defined $config->{type}->{$args->{type}}) {
        return { error => 1, message => 'type is invalid' };
    }

    if ($args->{key}) {
        # update
        _update($args);
        return { error => 0, type => $args->{type}, key => $args->{key} };
    } else {
        # create
        my $key = _create($args);

        unless ($key) {
            return { error => 1, message => 'create faild' };
        }

        return { error => 0, type => $args->{type}, key => $key };
    }
}

sub _update {
    my $args = shift;

    my $path = "$tmp/".$args->{key};
    my $fh;
    open $fh, '>', $path;
    print $fh $args->{input};
    close $fh;
}

sub _create {
    my $args = shift;

    my $checksum = md5_hex($args->{type}.$args->{input});
    my $path = "$tmp/$checksum";

    unless (-f $path) {
        my $fh;
        open $fh, '>', $path;
        print $fh $args->{input};
        close $fh;
        return $checksum;
    }

    return $checksum;
}

sub _get {
    my $args = shift;

    my $path = "$tmp/".$args->{key};

    if (-f $path) {
        my $fh;
        open $fh, $path;
        my $input = do{ local $/; <$fh> };
        close $fh;
        return $input;
    }

    return undef;
}

app->start;
__DATA__

@@ index.html.ep
% layout 'default';
% title 'NoPaste For Graph';
<h1><%= title %></h1>
<form action="/" method="post">
<textarea id="input" cols="100" rows="24" name="input"></textarea><br />
<select name="type">
% for my $k (keys %{$config->{type}}) {
  <option value="<%= $k %>"><%= $config->{type}->{$k}->{name} %></option>
% }
</select>
<input type="submit" />
</form>

@@ graph.html.ep
% layout 'default';
% title 'NoPaste For Graph';
<script type="text/javascript" src="https://www.google.com/jsapi"></script>
<script type="text/javascript">
  google.load("visualization", "1", {packages:["corechart"]});
  google.setOnLoadCallback(drawChart);
  function drawChart() {
    var data = new google.visualization.DataTable();

% my $i = 0;
% for my $c (@$columns) {
%   if ($i++) {
    data.addColumn('number', '<%= $c %>');
%   } else {
    data.addColumn('string', '<%= $c %>');
%   }
% }

    data.addRows([
% for my $r (@$rows) {
      [<%= b(join(",", @$r)) %>],
% }
    ]);

    var options = {
      width: <%= $size->{w} %>, height: <%= $size->{h} %>,
      title: '<%= title %>'
    };

    var chart = new google.visualization.<%= $config->{type}->{$type}->{type} %>Chart(document.getElementById('graph'));
    chart.draw(data, options);
  }
</script>
<div id="graph" />

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
