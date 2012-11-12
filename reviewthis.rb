require 'rubygems'
require 'sinatra'
require 'json'
require 'mustache/sinatra'
require 'pony'
require 'github_api'

configure do

   
  # regex's
  USER = /[^a-z0-9_]@([a-z0-9_]+)/i
  HASH = /[^a-z0-9_]#([a-z0-9_]+)/i # not used yet, but perhaps soon?
  REVIEW = /[^a-z0-9_](#reviewthis)[^a-z0-9_]+/i
  EMAIL = /\b([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4})\b/i
end

# production vars
configure :production do
  # only run on Heroku
  set :from, ENV['SENDGRID_USERNAME']
  set :via, :smtp
  set :via_options, {
    :address        => "smtp.sendgrid.net",
    :port           => "25",
    :authentication => :plain,
    :user_name      => ENV['SENDGRID_USERNAME'],
    :password       => ENV['SENDGRID_PASSWORD'],
    :domain         => ENV['SENDGRID_DOMAIN'],
  }
  
end

# development vars
configure :development, :test do
    set :from, 'reviewthis@localhost'
  set :via, :sendmail
  set :via_options, {}
end

helpers do
  # mail helper. Thnx Pony!
  def mail(vars)
    body = %{
      Hi #{vars[:username]}!

      #{vars[:commit_author]} wants you to review a recent commit to #{vars[:repo_name]} on github.

      Review it: #{vars[:commit_url]}

      Commit details
      ==============
        commit id:  #{vars[:commit_id]}
        committed:  #{vars[:commit_relative_time]} (#{vars[:commit_timestamp]})
        message:  #{vars[:commit_message]}  

      sent by #reviewthis
    }
    Pony.mail(:to => vars[:email], :from => options.from, :subject => "[#{vars[:repo_name]}] code review request from #{vars[:commit_author]}", :body => body, :via => options.via, :via_options => options.via_options) 
  end
end

# test!
get '/' do
  "#reviewthis @github!"
end

# the meat
post '/' do
  push = JSON.parse(params[:payload])
  
  # check every commit, not just the first
  push['commits'].each do |commit|

    message = commit['message']
    
    # we've got a #reviewthis hash
    if message.match(REVIEW)
    
      # set some template vars
      vars = {
        :commit_id => commit['id'],
        :commit_message => message,
        :commit_timestamp => commit['timestamp'],
        :commit_relative_time => Time.parse( commit['timestamp'] ).strftime("%m/%d/%Y at %I:%M%p"),
        :commit_author => commit['author']['name'],
        :commit_url => commit['url'],
        :repo_name => push['repository']['name'],
        :repo_url => push['repository']['url'],        
      }
      
      # let's find all the github users
      github_client = Github.new
      message.scan(USER) do |username|
        username = username[0]
        user = github_client.users.get(:user => username)
        vars[:username] = user.login
        vars[:email] = user.email
        mail(vars)
      end
    
      # now let's find any email addresses
      message.scan(EMAIL) do |email|
        vars[:username] = email
        vars[:email] = email
        mail(vars)
      end
  
    end
    
  end
  
  return
end