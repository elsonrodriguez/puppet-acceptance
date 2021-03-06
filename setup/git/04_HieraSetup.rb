test_name "Install and configure Hiera on Puppet Master..."

hieracfg = %q{---
:backend:
  - yaml
:hierarchy:
  - %{certname}
  - %{environment}
  - global

:yaml:
  :datadir: /etc/puppet/hieradata
}

def install_from_git(host, package, repo, revision)
  target = "#{SourcePath}/#{package}"

  step "Clone #{repo} if needed"
  on host, "test -d #{SourcePath} || mkdir -p #{SourcePath}"
  on host, "test -d #{target} || git clone #{repo} #{target}"

  step "Update #{package} and check out revision #{revision}"
  commands = ["cd #{target}",
              "remote rm origin",
              "remote add origin #{repo}",
              "fetch origin",
              "clean -fdx",
              "checkout -f #{revision}"]
  on host, commands.join(" && git ")
end

if (options[:hiera]) then
  step "Parse Hiera options"
  SourcePath  = "/opt/puppet-git-repos"
  GitHub      = 'git://github.com/puppetlabs'
  IsURI       = %r{^[^:]+://|^git@github.com:}
  IsGitHubURI = %r{(https://github.com/[^/]+/[^/]+)(?:/tree/(.*))$}
  
  if match = IsGitHubURI.match(options[:hiera]) then
    HieraRepo = match[1] + '.git'
    HieraRev  = match[2] || 'origin/master'
  elsif options[:hiera] =~ IsURI then
    repo, rev = options[:hiera].split('#', 2)
    HieraRepo = repo
    HieraRev  = rev || 'HEAD'
  else
    HieraRepo = "#{GitHub}/hiera.git"
    HieraRev  = options[:hiera]
  end

  hosts.each do |host|
    step "#{host} Install Hiera from git"
    install_from_git host, :hiera, HieraRepo, HieraRev
    version=''
    on host, "cd /opt/puppet-git-repos/hiera && git describe" do
      version = stdout.chomp
    end
    config[:version][:hiera] = version

    # REVISIT
    # very ugly hack to extract puppet conf dir from cygpath command,
    # need to think about adding this to library for Windows hosts
    dest_path=''
    case
    when host['platform'] =~ /windows/
      on host, '`cygpath -smF 35`/PuppetLabs/puppet/etc', :acceptable_exit_codes => (1..255)
      if stderr.chomp =~ /(C:\S*etc):/
        dest_path = $1
      else
        Log.warn "Unable to determine Puppet path on Windows host #{host} #{dest_path}"
      end
    else
      dest_path = host['puppetpath']
    end

    step "#{host}: Create Hiera config file hiera.yaml"
    create_remote_file(host, "#{dest_path}/hiera.yaml", hieracfg)
    on host, "chmod 644 #{dest_path}/hiera.yaml"

    step "#{host}: Create Hiera datadir"
    on host, "mkdir -p #{dest_path}/hieradata"
  end
else
  Log.notify "Skipping Hiera install"
  skip_test  "Skipping Hiera install"
end
