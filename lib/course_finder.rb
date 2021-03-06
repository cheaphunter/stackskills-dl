require 'mechanize'
require 'pry'

class CourseFinder

  STACKSKILLS_LOGIN_URL = "https://stackskills.com/sign_in"

  def self.run(input)
    finder = self.new(input)
    finder.execute do |course|
      course.download
    end
  end

  attr_accessor :input, :current_page, :courses

  def initialize(input)
    @input = input
  end

  def execute
    self.current_page = Mechanize.new.get(STACKSKILLS_LOGIN_URL)
    user_dashboard = login_user!

    return false unless user_dashboard
    self.current_page = user_dashboard
    get_course_links.each do |course_link|
      course = Course.new(url: course_link.text)
      lectures = analyze_course(course_link)
      course.add_lectures(lectures)

      yield course
    end
  end

  private
  def analyze_course(course_link)
    processed_lectures = []
    lectures = course_link.click
    lectures.links_with(href: /lectures/).each_with_index do |lecture, index|
      lecture_page = lecture.click
      processed_lectures << analyze_lecture(lecture_page, index)
    end

    processed_lectures
  end

  def analyze_lecture(lecture_page, index)
    lecture = Lecture.new(name: lecture_page.title, index: index)

    video = lecture_page.link_with(href: /.mp4/)
    if video
      lecture.add_video_attachment(video.href)
    else
      wistia_div = lecture_page.search('div.attachment-wistia-player')
      if wistia_div && wistia_div.count == 1
        video_id = wistia_div.first.attributes["data-wistia-id"].value
        lecture.add_wistia_video(video_id)
      end
    end

    pdf = lecture_page.link_with(href: /.pdf/)
    lecture.add_pdf(pdf) if pdf

    zipf = lecture_page.link_with(href: /.zip/)
    lecture.add_zip(zipf) if zipf

    lecture
  end

  def find_course(course_name)
    puts "Finding #{course_name} from your list of courses"
    course_href = course_name.split('/courses/').last
    course = current_page.link_with(href: Regexp.new(course_href.to_s))

    if course.nil?
      puts "Unable to find this course: #{course_name} from your list of courses."
    end

    course
  end

  def get_course_link_from_slug(url)
    course_page = Mechanize.new.get(url)
    form = course_page.forms.first
    course_id = form["course_id"]
    "https://stackskills.com/courses/enrolled/#{course_id}"
  end

  def get_course_links
    courses = []

    if input.has_course_input?
      course_url = input.course_url
      unless input.course_url_is_id?
        course_url = get_course_link_from_slug(input.course_url)
      end
      courses << find_course(course_url)
    else
      courses = current_page.links_with(href: %r{courses/(?!enrolled)})
    end

    courses.compact
  end

  def login_user!
    form = current_page.forms.first
    form['user[email]']    = input.email
    form['user[password]'] = input.password
    page = form.submit
    user_dashboard = page.link_with(href: %r{courses/enrolled})
    if user_dashboard
      puts "Login Successfully."
      return user_dashboard.click
    else
      puts "Invalid Login Credentials."
    end
  end
end
