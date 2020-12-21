require 'apartment/migrator'

module Audience1stRakeTasks
  def self.check_vars!
    %w(TENANT VENUE_FULLNAME).each do |var|
      raise "#{var} is required" unless ENV[var]
    end
  end
end

a1client = namespace :a1client  do
  desc "Add and seed new client named TENANT.  Don't forget to also add the tenant name to the `tenant_names` runtime environment variable, and set DNS resolution for <tenant>.audience1st.com."
  task :drop => :environment do
    raise 'TENANT is required' unless (tenant = ENV["TENANT"])
    puts "Dropping '#{tenant}'..."
    Apartment::Tenant.drop(tenant)
    puts "Dropped.  Don't forget to remove from Heroku DNS, from `tenant_names` envar, and from Sendgrid allowed domains."
  end

  task :create => :environment do
    raise 'TENANT is required' unless (tenant = ENV["TENANT"])
    puts "Creating '#{tenant}'..."
    Apartment::Tenant.create(tenant)
    puts "Seeding '#{tenant}'..."
    Apartment::Tenant.switch(tenant) do
      Apartment::Tenant.seed
    end
    puts "done"
  end

  desc "Configure (new) client named TENANT using VENUE_FULLNAME, using underscores for spaces. Don't forget to also add the tenant name to the `tenant_names` runtime environment variable, set DNS resolution for <tenant>.audience1st.com, and add the subdomain explicitly to Sendgrid settings."
  task :configure => :environment do
    Audience1stRakeTasks.check_vars!
    Apartment::Tenant.switch(ENV['TENANT']) do
      Option.first.update_attributes!(
        :sendgrid_domain    => "#{ENV['TENANT']}.audience1st.com",
        :venue              => ENV['VENUE_FULLNAME'].gsub(/_/,' '),
        :staff_access_only  => true )
      Customer.find_by(:first_name => 'Super', :last_name => 'Administrator').
        update_attributes!(:password => ('a'..'z').to_a.shuffle[0,8].join)
    end
    puts "Sendgrid domain configured, admin password randomized, and staff-only access enabled for #{ENV['VENUE_FULLNAME']} (#{ENV['TENANT']})"
  end

  desc "Set up new client TENANT using VENUE_FULLNAME, STRIPE_KEY, STRIPE_SECRET, all of which are required."
  task :provision => :environment do
    Audience1stRakeTasks.check_vars!
    a1client['create'].invoke
    a1client['configure'].invoke
    puts "Client provisioned. Next: Set up DNS subdomain resolution in Heroku, add to tenant_names envar, and add the subdomian in Sendgrid settings."
  end
end
