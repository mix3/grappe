#!/usr/bin/env perl
use Mojolicious::Lite;
use Digest::MD5 'md5_hex';
use utf8;

# Documentation browser under "/perldoc"
plugin 'PODRenderer';

# setting
my $config = {
    type => {
        line   => { key => 'Line',   name => '折れ線' },
        column => { key => 'Column', name => '棒'     },
    },
};

# init
my $tmp = app->home->rel_dir('tmp');
mkdir($tmp);

# ----------------------------------------------
# URL設計

# 新規作成画面    : get  /
# 生データ表示    : get  /graph/{id}
# 棒グラフ表示    : get  /column/{id}
# 線グラフ表示    : get  /line/{id}

# 生データ編集画面: get  /graph/{id}/edit
# 棒グラフ編集画面: get  /column/{id}/edit => /graph/{id}/edit redirect
# 線グラフ編集画面: get  /line/{id}/edit => /graph/{id}/edit redirect

# 新規作成        : post /
# 更新            : post /graph/{id}

# ----------------------------------------------
# under とか使ってもっと使い回せるはずなんだけど
# ちょっと良くわからなくなったのでベタ書き

get '/' => sub {
    my $self = shift;
    $self->render(config => $config);
} => 'index';

get '/graph/:key' => sub {
    my $self = shift;

    my $key = $self->param('key');

    my $input = _get({ key => $key });

    unless ($input) {
        return $self->render_not_found;
    }

    $self->render(
        input => $input
    );
} => 'raw_view';

get '/:type/:key' => sub {
    my $self = shift;

    my $key = $self->param('key');

    my $input = _get({ key => $key });

    unless ($input) {
        return $self->render_not_found;
    }

    my $columns = [];
    my $rows    = [];

    my $i = 0;
    for my $line (split(/\r?\n/, $input)) {
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
        type    => $self->param('type') || 'line',
    );
} => 'view';

get '/graph/:key/edit' => sub {
    my $self = shift;

    my $key = $self->param('key');

    my $input = _get({ key => $key });

    unless ($input) {
        return $self->render_not_found;
    }

    $self->render(
        config => $config,
        input  => $input,
        key    => $key,
    );
} => 'raw_edit';

get '/:type/:key/edit' => sub {
    my $self = shift;
    $self->redirect_to('/graph/'.$self->param('key').'/edit');
};

post '/' => sub {
    my $self = shift;

    my $type  = $self->param('type') || 'graph';
    my $input = $self->param('input');
    my $key   = $self->param('key');

    my $result = _create_or_update({
        input => $input,
        key   => $key,
    });

    if ($result->{error}) {
        $self->render_exception($result->{message});
    }

    $self->redirect_to('/'.$type.'/'.$result->{key});
};

post '/graph/:key' => sub {
    my $self = shift;

    my $type  = $self->param('type') || 'graph';
    my $input = $self->param('input');
    my $key   = $self->param('key');

    my $result = _create_or_update({
        input => $input,
        key   => $key,
    });

    if ($result->{error}) {
        $self->render_exception($result->{message});
    }

    $self->redirect_to('/'.$type.'/'.$result->{key});
};

sub _create_or_update {
    my $args = shift;

    unless ($args->{input}) {
        return { error => 1, message => 'require param: input' };
    }

    if ($args->{key}) {
        # update
        _update($args);
        return { error => 0, key => $args->{key} };
    } else {
        # create
        my $key = _create($args);

        unless ($key) {
            return { error => 1, message => 'create faild' };
        }

        return { error => 0, key => $key };
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

    my $checksum = md5_hex($args->{input});
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
% title 'Grappe';
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

@@ raw_view.html.ep
% layout 'default';
% title 'Grappe';
<h1><%= title %></h1>
<pre><%= $input %></pre>

@@ view.html.ep
% layout 'default';
% title 'Grappe';
<h1><%= title %></h1>
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
      [<%= Mojo::ByteStream->new(join(",", @$r)) %>],
% }
    ]);

    var options = {
      width: <%= $size->{w} %>, height: <%= $size->{h} %>,
      title: '<%= title %>'
    };

    var chart = new google.visualization.<%= $config->{type}->{$type}->{key} %>Chart(document.getElementById('graph'));
    chart.draw(data, options);
  }
</script>
<div id="graph" />

@@ raw_edit.html.ep
% layout 'default';
% title 'Grappe';
<h1><%= title %></h1>
<form action="/graph/<%= $key %>" method="post">
<textarea id="input" cols="100" rows="24" name="input"><%= $input %></textarea><br />
<select name="type">
% for my $k (keys %{$config->{type}}) {
  <option value="<%= $k %>"><%= $config->{type}->{$k}->{name} %></option>
% }
</select>
<input type="submit" />
</form>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
