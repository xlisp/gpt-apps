require 'openai'
require 'erb'
require 'json'
require 'open-uri'

## from : https://ruby-china.org/hooopo , 只是做一个代码占位实例，后期其他语言重写之

class GithubUserInfoTool 

  attr_reader :input

  def initialize(input: )
    @input = input.to_s.gsub(/^"|"$/, '')
  end

  def self.description
    <<~DESC
    Return the Github user info, include location, bio, followers_count, followings_count, public_repos_count, created_at etc with json format. The action input is the GitHub user's login name, without quotation marks.
    DESC
  end

  def call
    puts "Calling GithubUserInfoTool with input -> #{input}"
    JSON.parse(URI.open("https://api.github.com/users/#{input}").read).slice("bio", "twitter_username", "location", "followers", "following", "created_at", "public_repos")
  end
end

class CalculatorTool

  attr_reader :input

  def initialize(input: )
    @input = input
  end

  def self.description
    <<~DESC
      Runs a calculation and returns the number - uses Ruby so be sure to use floating point syntax if necessary
    DESC
  end

  def call
    puts "Calling CalculatorTool with input -> #{input}"
    eval(input).to_s rescue "I don't know how to calculate that"
  end
end

class ReAct
  attr_reader :debug, :access_token, :question, :max_retries, :client, :tools
  
  def initialize(question: , access_token: , debug: false, max_retries: 5, tools: [])
    @client = OpenAI::Client.new(access_token: access_token)
    @debug = debug
    @question = question 
    @tools = tools
  end

  def prompt_temple
    <<~PROMPT
    Answer the following questions as best you can. You have access to the following tools:

    <% tools.each do |tool| %>
    <%= tool %>: <%= tool.description %>
    <% end %>

    Use the following format for each step. You can take multiple steps, but never number them. If the tools provided above cannot answer the question, feel free to improvise and begin your response start with "Final Answer:".
    In regards to things unrelated to the tool mentioned above, you don't need the Thought and Action modes.

    Question: the input question you must answer
    Thought: you should always think about what to do
    Action: the action to take, should be one of [<%= tools.map(&:to_s).join(", ") %>] if it needed.
    Action Input: the input to the action
    Observation: the result of the action
    ... (this Thought/Action/Action Input/Observation can repeat N times)
    Thought: I now know the final answer
    Final Answer: the final answer to the original input question

    Begin!

    Question: <%= question %>
    Thought: <%= thought %>
    PROMPT
  end

  def call
    thought = ""
    i = 0
    loop do 
      prompt = ERB.new(prompt_temple).result(binding).strip
      puts i.to_s * 10 if debug
      puts prompt if debug
      messages = messages = [
        { role: "user", content: prompt }
      ]
      response = client.chat(
        parameters: {
            model: "gpt-3.5-turbo",
            messages: messages,
            temperature: 0.6,
            stop: "Observation: " # Inject observation of AI, and use the custom tool to get the observation
       }
      )
      
      output = response.dig("choices", 0, "message", "content")
      puts "output from OpenAI 👇"
      puts output 
      puts "\n\n"
      
      # extract the final answer, action and action input from the output
      answer = output[/Final Answer:(.*?)$/m, 1]
      action = output[/^Action( \d+)?: (.*?)$/m, 2]
      action_input = output[/^Action Input( \d+)?: (.*?)$/m, 2]
      
      # if the action is one of the tools, we call the tool with the action input, and get the observation
      if action && action_input 
        if tool = tools.find{|tool| tool.to_s == action}
          observation = tool.new(input: action_input.strip).call

          # Append the Thought/Action/Action Input/Observation to the last of original prompt, and use it as the new prompt
          thought = thought + output 
          thought = thought + "Observation: #{observation}\n"
        else 
          # some times, the AI think too much, and the action is not one of the tools, so we just return the output without the last Thought/Action/Action Input/Observation
          return output.to_s.gsub(/\nAction:(.*?)\nAction Input:(.*?)\n$/m, '')
        end
      else
        if answer
          return answer.strip
        else
          return "I don't know how to answer this question"
        end
      end
      i = i+1
    end
  end
end

ReAct.new(access_token: ENV["OPENAI_API_TOKEN"], question: "tj的GitHub粉丝数除以2是多少？", tools: [CalculatorTool, GithubUserInfoTool], debug: true).call
