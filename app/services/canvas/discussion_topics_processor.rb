class Canvas::DiscussionTopicsProcessor

  include CanvasRelativeUrlHelper

  attr_accessor :request_object, :top_level_post, :edit_post, :reply_to_post, :course

  def initialize(conf)
    @request_object  = conf[:request_object]
    @top_level_post  = PointsConfiguration.where({interaction: 'DiscussionTopic'}).first
    @edit_post       = PointsConfiguration.where({interaction: 'DiscussionEdit'}).first
    @course          = conf[:course] || AppConfig::CourseConstants.course
  end

  def call(discussions)

    canvas_student_ids = Student.get_students_by_canvas_id.keys
    if discussions.respond_to?(:each)
      discussions.each do |discussion|
        ## API return data might be 'dirty'
        author_id = discussion && discussion['author'] && discussion['author']['id']
        if (author_id && !canvas_student_ids.include?(author_id.to_i))
          Student.create_by_canvas_user_id(author_id)
          canvas_student_ids << author_id.to_i
        end
        msg = discussion['message'] || ''
        title = discussion['title'] || ''
        is_assigned_discussion = discussion['assignment_id'] ? true : false
        discussion_id = discussion['id']   # discussion's ID, not author's
        base_params = { canvas_updated_at: discussion['last_reply_at'], body: msg + title, scoring_item_id: discussion_id  }
        previous_scoring_record = Activity.where({scoring_item_id: discussion_id.to_s,
            reason: ['DiscussionTopic', 'DiscussionEdit']}).order('updated_at DESC').first

        if previous_scoring_record
          # we can only tell if this top-level entry was edited from comparing the message values,
          ##  as the updated_at is changed whenever there are child-level changes
          process_entries =  (previous_scoring_record.canvas_updated_at < discussion['last_reply_at'])
          if  ((discussion['message'].to_s + discussion['title'].to_s) != previous_scoring_record.body)  # edit, even trivial ones
            Activity.score!(base_params.merge({ canvas_user_id: previous_scoring_record.canvas_user_id,
                                                score: edit_post.active,
                                                assigned_discussion: is_assigned_discussion,
                                                reason: 'DiscussionEdit', delta: edit_post.points_associated}) )
          end
        else   # new post
          process_entries = true   # post is new, so last_reply_at is irrelevant -- always check for children
          if author_id
            Activity.score!(base_params.merge({ reason: 'DiscussionTopic', delta: top_level_post.points_associated,
                                                score: top_level_post.active,
                                                assigned_discussion: is_assigned_discussion,
                                                canvas_user_id: author_id}))
          end
        end

        ## if there are replies to this discussion_topic
        if (discussion["discussion_subentry_count"]  > 0) && process_entries
          request_path = course_api_url(course: course, mid_variable: discussion_id.to_s, mid_const: :discussion_topics, final_url: :entries)
          entry_processor  = Canvas::DiscussionEntriesProcessor.new({request_object: request_object})
          paged_processor = Canvas::PagedApiProcessor.new({ handler: entry_processor })
          paged_processor.call(request_path)
        end
      end
    end

  end

end
