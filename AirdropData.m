classdef AirdropData < handle
    % Top level class definition for various helper methods
    % e.g. Data windowing, trimming, etc. so we're not copy/pasting things
    % between class definitions
    properties
    end
    
    methods
        function [dataObj] = AirdropData()
            if nargout == 0
                clear dataObj
            end
        end
    end
    
    methods (Static)
        function [date] = getdate()
            % Generate current local timestamp and format according to
            % ISO 8601: yyyy-mm-ddTHH:MM:SS+/-HH:MMZ
            if ~verLessThan('MATLAB', '8.4')  % datetime added in R2014b
                timenow = datetime('now', 'TimeZone', 'local');
                formatstr = sprintf('yyyy-mm-ddTHH:MM:SS%sZ', char(tzoffset(timenow)));
            else
                UTCoffset = -java.util.Date().getTimezoneOffset/60;  % See what Java thinks your TZ offset is
                timenow = clock;
                formatstr = sprintf('yyyy-mm-ddTHH:MM:SS%i:00Z', UTCoffset);
            end
            
            date = datestr(timenow, formatstr);
        end
        
        
        function [nlines] = countlines(filepath)
            % COUNTLINES counts the number of lines present in the 
            % specified file, filepath, passed as an absolute path.
            fID = fopen(filepath, 'rt');
            
            blocksize = 16384;  % Size of block to read in, bytes
            nlines = 0;
            while ~feof(fID)
                % Read in CSV file as binary file in chunks, count the
                % number of line feed characters (ASCII 10)
                nlines = nlines + sum(fread(fID, blocksize, 'char') == char(10));
            end
            
            fclose(fID);
        end
        
        
        function [dataidx] = windowdata(ls, waitboxBool)
            % WINDOWDATA generates two draggable vertical lines in the 
            % parent axes of the input lineseries, ls, for the user to
            % use to window the data plotted with the lineseries.
            % 
            % Execution is blocked by UIWAIT and MSGBOX to allow the user 
            % to zoom/pan the axes and manipulate the window lines as 
            % desired. Once the dialog is closed the data indices of the 
            % window lines in the XData of the input lineseries is returned
            % as dataidx.
            %
            % An optional secondary boolean input can be provided to
            % control whether or not execution is blocked by UIWAIT and
            % MSGBOX or simpy by UIWAIT. If waitboxbool is passed as false,
            % only UIIWAIT is called and it is assumed that the user has
            % something else set up to call UIRESUME to resume MATLAB's
            % execution. If waitboxbool is not false or does not exist,
            % UIWAIT and MSGBOX are used to block execution until the
            % dialog box is closed.
            ax = ls.Parent;
            fig = ax.Parent;
            
            oldbuttonup = fig.WindowButtonUpFcn;  % Store existing WindowButtonUpFcn
            fig.WindowButtonUpFcn = @AirdropData.stopdrag;  % Set the mouse button up Callback
            
            % Create our window lines, set the default line X locations at
            % 25% and 75% of the axes limits
            currxlim = xlim(ax);
            axeswidth = currxlim(2) - currxlim(1);
            dragline(1) = line(ones(1, 2)*axeswidth*0.25, ylim(ax), ...
                            'Color', 'g', 'ButtonDownFcn', @(s,e)AirdropData.startdrag(s, ax));
            dragline(2) = line(ones(1, 2)*axeswidth*0.75, ylim(ax), ...
                            'Color', 'g', 'ButtonDownFcn', @(s,e)AirdropData.startdrag(s, ax));
            
            % Add appropriate listeners to the X and Y axes to ensure
            % window lines are visible and the appropriate height
            xlisten = addlistener(ax, 'XLim', 'PostSet', @(s,e)AirdropData.checklinesx(ax, dragline));
            ylisten = addlistener(ax, 'YLim', 'PostSet', @(s,e)AirdropData.changelinesy(ax, dragline));
            
            % Unless passed a secondary, False argument, use uiwait to 
            % allow the user to manipulate the axes and window lines as 
            % desired. Otherwise it is assumed that uiresume is called
            % elsewhere to unblock execution
            if nargin == 2 && ~waitboxBool
                uiwait
            else
                uiwait(msgbox('Window Region of Interest Then Press OK'))
            end
            
            % Set output
            % TODO: Make sure we don't go beyond our data, should be caught
            % by the drag functions but make sure there aren't edge cases
            dataidx(1) = find(ls.XData >= dragline(1).XData(1), 1);
            dataidx(2) = find(ls.XData >= dragline(2).XData(1), 1);
            dataidx = sort(dataidx);
            
            % Clean up
            delete([xlisten, ylisten]);
            delete(dragline)
            fig.WindowButtonUpFcn = oldbuttonup;
        end


        function [dataidx] = fixedwindowdata(ls, windowlength, waitboxBool)
            % FIXEDWINDOWDATA generates a draggable rectangular patch in 
            % the parent axes of the input lineseries, ls, for the user to
            % use to window the data plotted with the lineseries. The
            % length of the data window, windowlength, is used under the
            % assumption that the input lineseries is a time vs. data plot
            % where time is in seconds.
            % 
            % Execution is blocked by UIWAIT and MSGBOX to allow the user 
            % to zoom/pan the axes and manipulate the window lines as 
            % desired. Once the dialog is closed the data indices of the 
            % window lines in the XData of the input lineseries is returned
            % as dataidx.
            %
            % An optional secondary boolean input can be provided to
            % control whether or not execution is blocked by UIWAIT and
            % MSGBOX or simpy by UIWAIT. If waitboxbool is passed as false,
            % only UIIWAIT is called and it is assumed that the user has
            % something else set up to call UIRESUME to resume MATLAB's
            % execution. If waitboxbool is not false or does not exist,
            % UIWAIT and MSGBOX are used to block execution until the
            % dialog box is closed.
            ax = ls.Parent;
            fig = ax.Parent;
            fig.WindowButtonUpFcn = @AirdropData.stopdrag;  % Set the mouse button up Callback on figure creation
            
            currxlim = xlim(ax);
            currylim = ylim(ax);
            axeswidth = currxlim(2) - currxlim(1);

            leftx = axeswidth*0.25;
            rightx = leftx + windowlength;
            vertices = [leftx, currylim(1); ...   % Bottom left corner
                        rightx, currylim(1); ...  % Bottom right corner
                        rightx, currylim(2); ...  % Top right corner
                        leftx, currylim(2)];      % Top left corner
            dragpatch = patch('Vertices', vertices, 'Faces', [1 2 3 4], ...
                                'FaceColor', 'green', 'FaceAlpha', 0.3, ...
                                'ButtonDownFcn', {@AirdropData.startdragwindow, ax});
            
            % Unless passed a tertiary, False argument, use uiwait to 
            % allow the user to manipulate the axes and window lines as 
            % desired. Otherwise it is assumed that uiresume is called
            % elsewhere to unblock execution
            if nargin == 3 && ~waitboxBool
                uiwait
            else
                uiwait(msgbox('Window Region of Interest Then Press OK'))
            end
            
            % Set output
            dataidx(1) = find(ls.XData >= dragpatch.XData(1), 1);
            dataidx(2) = find(ls.XData >= dragpatch.XData(2), 1);
            dataidx = sort(dataidx);
            
            % Clean up
            delete(dragpatch)
            fig.WindowButtonUpFcn = '';
        end
    end
    
    methods (Static, Hidden, Access = protected)
        function startdrag(lineObj, ax)
            % Helper function for data windowing, sets figure
            % WindowButtonMotionFcn callback to dragline helper
            % while line is being clicked on & dragged
            ax.Parent.WindowButtonMotionFcn = @(s,e)AirdropData.linedrag(ax, lineObj);
        end
        
        
        function stopdrag(hObj, ~)
            % Helper function for data windowing, clears figure window
            % WindowButtonMotionFcn callback when mouse button is released
            % after dragging the line
            hObj.WindowButtonMotionFcn = '';
        end
        
        
        function checklinesx(ax, dragline)
            % Helper function for data windowing, checks the X indices of
            % the vertical lines to make sure they're still within the X
            % axis limits of the data axes object
            currxlim = ax.XLim;
            currlinex(1) = dragline(1).XData(1);
            currlinex(2) = dragline(2).XData(1);
            
            % Set X coordinate of any line outside the axes limits to the
            % axes limit
            if currlinex(1) < currxlim(1)
                dragline(1).XData = [1, 1]*currxlim(1);
            end
            
            if currlinex(1) > currxlim(2)
                dragline(1).XData = [1, 1]*currxlim(2);
            end
            
            if currlinex(2) < currxlim(1)
                dragline(2).XData = [1, 1]*currxlim(1);
            end
            
            if currlinex(2) > currxlim(2)
               dragline(2).XData = [1, 1]*currxlim(2);
            end
            
        end
        
        
        function changelinesy(ax, dragline)
            % Helper function for data windowing, sets the height of both
            % vertical lines to the height of the axes object
            dragline(1).YData = ylim(ax);
            dragline(2).YData = ylim(ax);
        end

        
        function linedrag(ax, lineObj)
            % Helper function for data windowing, updates the x coordinate
            % of the dragged line to the current location of the mouse
            % button
            currentX = ax.CurrentPoint(1, 1);
            
            % Prevent dragging outside of the current axes limits
            if currentX < ax.XLim(1)
                lineObj.XData = [1, 1]*ax.XLim(1);
            elseif currentX > ax.XLim(2)
                lineObj.XData = [1, 1]*ax.XLim(2);
            else
                lineObj.XData = [1, 1]*currentX;
            end
        end
        
        function startdragwindow(patchObj, ed, ax)
            ax.Parent.WindowButtonMotionFcn = @(s,e)AirdropData.dragwindow(ax, patchObj);
            patchObj.UserData = ed.IntersectionPoint(1);  % Store initial click location to find a delta later
        end
        
        
        function dragwindow(ax, patchObj)
            oldmouseX = patchObj.UserData;
            newmouseX = ax.CurrentPoint(1);
            patchObj.UserData = newmouseX;
            
            dx = newmouseX - oldmouseX;
            newpatchX = patchObj.XData + dx; 
            
            % Prevent dragging outside of the current axes limits
            if newpatchX(1) < ax.XLim(1)
                newdx = patchObj.XData - ax.XLim(1);
                patchObj.XData = patchObj.XData + newdx;
            elseif newpatchX(2) > ax.XLim(2)
                newdx = patchObj.XData - ax.XLim(2);
                patchObj.XData = patchObj.XData + newdx;
            else
                patchObj.XData = newpatchX;
            end
        end
    end
end