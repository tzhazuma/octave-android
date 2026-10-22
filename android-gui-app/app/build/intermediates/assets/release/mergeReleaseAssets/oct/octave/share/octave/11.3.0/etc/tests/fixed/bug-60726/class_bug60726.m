classdef class_bug60726 < handle
  methods
    function varargout = subsref (obj, s)
      varargout = num2cell (repelem (nargout, max (nargout, 1)));
    end
  end
end
