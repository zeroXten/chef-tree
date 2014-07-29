= chef-tree.rb =

A ruby script that prints a coloured tree of cookbook dependencies. It is designed to work along side berkshelf, but does not require berkshelf nor does it replace berks viz.

It works by reading recipes and looking for all include\_recipe calls.

= Installing it =

Just clone this repo then install the gems

    $ git clone https://
    $ cd chef-tree
    $ bundle install

= Configuration =

Chef-tree needs a list of directories that contain cookbooks.

    $ cat <<-EOF > ~/.chef-tree.json
    {
      "cookbook_paths": [
        "/home/user/src/chef/cookbooks",
        "/home/user/src/chef/roles"
      ]
    }
    EOF
    ^D

= Running it =

A very simple cookbook might look something like this:

    $ chef-tree.rb
     sensu_spec::default (0.7.0 START)
         sensu_spec::client
             sensu_spec::base
             sensu_spec::definitions
             apt::default (~> 2.3)
             yum-epel::default (~> 0.2)
             sensu_spec::_helper

